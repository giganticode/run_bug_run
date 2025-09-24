require 'open3'
require 'logger'
require 'io/wait'
require 'tmpdir'
require 'tempfile'

require 'run_bug_run/program_output_matcher'
require 'run_bug_run/test_run'
require 'run_bug_run/test_worker_pool'
require 'run_bug_run/sandboxing'

module RunBugRun
  class TestRunner
    # largest test output is 1098
    MAX_OUTPUT_LENGTH = 1024 * 2
    MAX_ERROR_OUTPUT_LENGTH = 1024 * 4
    READ_BLOCKSIZE = 512
    WRITE_BLOCKSIZE = 512
    NO_RLIMIT_LANGUAGES = %i[java javascript go].freeze
    JAVA_CLASS_REGEX = /^\s*(?:(?:public|static|protected|private|final)\s+)*class\s+([a-zA-Z0-9_]+)/

    DEFAULT_TIMEOUT = 5

    Run = Struct.new(
      :status,
      :bug_id,
      :bug_version,
      :bug_variant,
      :test_id,
      :output,
      :error_output,
      :trace_output,
      :expected_output,
      :wall_time,
      keyword_init: true) do
        def pass? = status == :pass
        def error? = status == :error
        def fail? = status == :fail
        def timeout? = status == :timeout
    end

    Test = Struct.new(
      :id, # DB id of test
      :problem_id,
      :input,
      :output,
      keyword_init: true
    )

    CaptureResult = Struct.new(:output, :error_output, :trace_output, :write_status, :exit_status, :epipe, :start_time, :end_time) do
      def wall_time
        end_time - start_time
      end
    end

    def initialize(program, tests, abort_on_timeout: false, abort_on_fail: false,
                  abort_on_error: false, truncate_output: true, timeout: DEFAULT_TIMEOUT, logger_level: Logger::WARN, logger: nil, trace_fd: nil)

      @truncate_output = truncate_output
      @program = program
      @program_language = @program.language.to_sym
      @tests = tests
      @abort_on_timeout = abort_on_timeout
      @abort_on_fail = abort_on_fail
      @abort_on_error = abort_on_error
      @timeout = timeout
      @trace_fd = trace_fd

      if logger
        @logger = logger
      else
        @logger = defined?(Rails) ? Rails.logger : ::Logger.new($stdout)
        @logger.level = logger_level
      end
    end

    def run!
      @counters = {timeout: 0, fail: 0, error: 0}
      @aborted = false

      @logger.debug "Running #{@program.bug_id} on #{@tests.map(&:id)}"
      return [] if @tests.empty?
      compile_and_run
    end

    def aborted? = @aborted

    class CompilationError < StandardError; end
    class BWrapError < StandardError; end

    def before_run(&block)
      @before_run_callback = block
    end

    def after_run(&block)
      @after_run_callback = block
    end

    private


    def call_before_run_callback(program, test)
      @before_run_callback&.call program, test
    end

    def call_after_run_callback(program, test, run)
      @after_run_callback&.call program, test, run
    end

    def truncate_output(output, max_size)
      output.length > max_size ? "#{output[0...max_size]}<truncated>" : output
    end

    def run_compiler(cmd, input_filename, input, *args, env: {})
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          File.write(File.join(dir, input_filename), input)
          output, status = Open3.capture2e(env.merge('LANG' => 'en_US.UTF-8'), *cmd, input_filename, *args, chdir: dir)
          if status.exitstatus.zero?
            yield dir
          else
            # FIXME: pass error message
            raise CompilationError.new(output)
          end
        end
      end
    end

    def compile_java(&block)
      # we ignore packages to simplify compilation
      code = @program.code.sub(/package\s+([a-zA-Z0-9_.]+)\s*;/, '')
      class_name = @program.main_class || 'Main'
      # class_names = code.scan(JAVA_CLASS_REGEX).flatten
      # class_name = class_names.first if class_names.size == 1
      # class_name ||= find_java_main_class(@program)
      raise CompilationError, 'missing main class' if class_name.nil?

      run_compiler(['javac', '-encoding', 'UTF-8'], "#{class_name}.java", code) do |tmp_dir|
        class_filenames = Dir[File.join(tmp_dir, '*.class')]
        # sandbox_filenames = class_filenames.map { File.join('/tmp', File.basename(_1)) }
        block[class_filenames, { class_name: class_name }]
      end
    end

    def compile_c(cc, ext, &block)
      run_compiler(cc, "file.#{ext}", @program.code, '-lm') do |tmp_dir|
        block[File.join(tmp_dir, 'a.out'), {}]
      end
    end

    def compile_go(&block)
      run_compiler(['go', 'build', '-o', 'a.out'], 'file.go', @program.code, env: {'GOCACHE' => '/tmp/'} ) do |tmp_dir|
        block[File.join(tmp_dir, 'a.out'), {}]
      end
    end

    def compile_c_sharp(&block)
      run_compiler(['mcs', '-out:out.exe', '-debug'], 'file.cs', @program.code) do |tmp_dir|
        block[File.join(tmp_dir, 'out.exe'), {}]
      end
    end

    def dummy_compile(&block)
      Dir.mktmpdir(nil, '/tmp') do |dir|
        Dir.chdir(dir) do
          file_path = File.join(dir, "file.#{@program.filename_ext}")
          File.write(file_path, @program.code)
          block[file_path, {}]
        end
      end
    end

    def compile(&block)
      case @program_language
      when :java
        compile_java(&block)
      when :cpp
        compile_c('g++', 'cpp', &block)
      when :c
        compile_c('gcc', 'c', &block)
      when :go
        compile_go(&block)
      when :c_sharp
        compile_c_sharp(&block)
      else
        dummy_compile(&block)
      end
    end

    def cmd(filename, context)
      case @program_language
      when :ruby
        # ['/usr/bin/ruby', '--disable-gems', filename]
        # --disable-gems might be removed in the future, see https://bugs.ruby-lang.org/issues/17684
        # also, parts of the standard libraries are shipped as gems (e.g., matrix)
        # which some programs in RBR rely on
        ['/usr/bin/ruby', filename]
      when :python
        ['/usr/bin/python3', filename]
      when :php
        ['/usr/bin/php', filename]
      when :javascript
        ['/usr/bin/node', '--max-old-space-size=512', filename]
      when :c, :cpp, :go
        ['./a.out']
      when :java
        ['/usr/bin/java', '-mx512m', '-XX:TieredStopAtLevel=1', context.fetch(:class_name)]
        # cmd << '/usr/lib/jvm/java-17-openjdk-amd64/bin/java' <<
      when :c_sharp
        ['/usr/bin/mono', '--debug', 'out.exe']
      else
        raise "language #{@program_language} is not supported"
      end
    end

    def abort?(status, abort_count, status1, status2=status1)
      if abort_count && (status == status1 || status == status2)
        @counters[status1] += 1
        if abort_count == true || @counters.fetch(status1) >= abort_count
          @logger.debug "#{@counters.fetch(status1)} #{status1}s...aborting"
          return true
        end
      end
      false
    end

    def run_all_tests(filename, context)
      @tests.each_with_object([]) do |test, results|
        result = run_test(filename, context, test)
        if result
          status = result.status
          results << result

          return results if abort?(status, @abort_on_timeout, :timeout, :timeout2) ||
                            abort?(status, @abort_on_fail, :fail) ||
                            abort?(status, @abort_on_error, :error)
        end
      end
    end

    def read_with_timeout(io, timeout, log_tag, block_size: READ_BLOCKSIZE, max_output_length: MAX_ERROR_OUTPUT_LENGTH)
      buf = StringIO.new
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      loop do
        runtime = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
        @logger.debug { "Runtime: #{runtime} (buffer size #{log_tag}: #{buf.size})" }
        return :timeout if runtime >= timeout

        read_result = io.read_nonblock(block_size, exception: false)
        @logger.debug { "Read result (#{log_tag}): #{read_result.inspect} #{log_tag}" }
        if read_result == :wait_readable
          select_result = IO.select([io], nil, nil, 0.1)
          next if select_result # there is something to read, restart loop
        elsif read_result.nil?
          # eof, done reading
          break
        else
          buf.write read_result
          # hit maximum output length, stopping
          break if max_output_length && buf.size >= max_output_length
        end
      rescue IOError => e
        # protected against closed stream errors
        @logger.debug("IO error while reading program output (#{log_tag}): #{e.message}")
        break
      end
      buf.string
    end

    def write_with_timeout(io, buf, timeout)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      written = 0
      buf.rewind

      return 0 if buf.eof?

      chunk = buf.read(WRITE_BLOCKSIZE)

      loop do
        runtime = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
        @logger.debug { "write Runtime: #{runtime} (buffer size: #{buf.size})" }
        return :timeout if runtime >= timeout

        write_result = io.write_nonblock(chunk, exception: false)
        if write_result == :wait_writable
          select_result = IO.select(nil, [io], nil, 0.1)
          next if select_result # writable again, restart loop
        else
          written += write_result

          # otherwise prepare next chunk
          # if the entire chunk was successfully written, read new one
          # from buffer, otherwise slice unwritten part off of current chunk
          if write_result != chunk.size
            chunk = chunk.byteslice(write_result..)
          else
            # done if eof
            break if buf.eof?
            chunk = buf.read(WRITE_BLOCKSIZE)
          end
        end
      end

      written
    end


    def capture3_with_timeout(cmd, env: {}, timeout:, stdin_data:, binmode: false, **opts)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      if @trace_fd
        trace_out, trace_in = IO.pipe
        trace_out.sync = true
        trace_in.sync = true
        opts = opts.merge @trace_fd => trace_in
      end

      # Yes, I am paranoid
      Sandboxing.check_in_sandbox!

      Open3.popen3(env, *cmd, opts) do |stdin, stdout, stderr, wait_thread|
        if binmode
          stdin.binmode
          stdout.binmode
          stderr.binmode
        end
        out_reader = Thread.new do
          read_with_timeout stdout, timeout, 'out'
        end
        err_reader = Thread.new do
          read_with_timeout stderr, timeout, 'err'
        end

        if @trace_fd
          trace_reader = Thread.new do
            read_with_timeout trace_out, timeout, 'trace', block_size: 1024, max_output_length: nil
          end
        end

        epipe = false

        begin
          stdin_buf = StringIO.new

          stdin_buf.write(stdin_data)
          # some inputs lack final newline
          stdin_buf.write "\n" unless stdin_data.end_with?("\n")

          write_status = write_with_timeout(stdin, stdin_buf, timeout)
        rescue Errno::EPIPE
          epipe = true
        end

        begin
          stdin.close
        rescue Errno::EPIPE
          epipe = true
        end

        if @trace_fd
          trace_in.close
        end

        out_value = out_reader.value
        err_value = err_reader.value
        trace_value = @trace_fd ? trace_reader.value : nil

        until_timeout = timeout - (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time)
        wait_thread_timed_out = wait_thread.join([0, until_timeout].max).nil?

        if wait_thread_timed_out
          # HACK: the program timed out, we override write_status
          # which will cause the pid to be killed and the final status be set to timeout
          # the original write_status value (i.e., number of written bytes) is not needed
          write_status = :timeout
        end

        if out_value == :timeout || err_value == :timeout || (trace_value && trace_value == :timeout) || write_status == :timeout
          begin
            @logger.debug { "Killing process #{wait_thread.pid}" }
            Process.kill 'KILL', wait_thread.pid
          rescue Errno::ESRCH
            @logger.info "pid was no longer alive"
          end
        end

        exit_status = wait_thread.value

        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        if @trace_fd
          trace_out.close
        end
        CaptureResult.new out_value, err_value, trace_value, write_status, exit_status, epipe, start_time, end_time
      end
    end

    def program_specifier
      "#{@program.bug_id}/#{@program.bug_version}/#{@program.bug_variant}"
    end

    def run_test(filename, context, test)
      call_before_run_callback(@program, test)

      test_input = test.input
      expected_output = test.output.strip

      popen_opts = {
        unsetenv_others: true,
        rlimit_cpu: 10
      }
      env = {
        'OPENBLAS_NUM_THREADS' => '1',
        'GOTO_NUM_THREADS' => '1',
        'OMP_NUM_THREADS' => '1',
        'LANG' => 'en_US.UTF-8',
      }

      cmd = cmd(filename, context)

      status = nil

      # Limit causes JVM to crash. We can limit memory using JVM anyway
      popen_opts[:rlimit_as] = 512 * 1024 * 1024 unless NO_RLIMIT_LANGUAGES.include?(@program_language)

      @logger.debug("Running program for bug #{@program.bug_id} on test #{test.id}")

      capture_result = capture3_with_timeout(cmd, env: env, timeout: @timeout, stdin_data: test_input, **popen_opts)
      output = capture_result.output
      error_output = capture_result.error_output
      write_status = capture_result.write_status
      exit_status = capture_result.exit_status
      epipe = capture_result.epipe

      if write_status.is_a?(Integer)
        test_input_bytesize = test_input.bytesize

        # if test input lacks final newline write_status is one byte longer than input
        if write_status != test_input_bytesize && write_status != test_input_bytesize + 1
          raise "test input has not been fully written (written #{write_status} of #{test_input_bytesize} bytes)" 
        end
      end

      if output == :timeout || error_output == :timeout || write_status == :timeout
        status = :timeout
        output = nil
        error_output = nil
      end

      output = output&.size&.positive? ? output.encode('UTF-8', invalid: :replace, replace: '') : nil
      error_output = error_output&.size&.positive? ? error_output.encode('UTF-8', invalid: :replace, replace: '') : nil

      output = output&.strip&.delete "\u0000"
      error_output = error_output&.delete "\u0000"

      if error_output =~ /bwrap:/
        raise BWrapError.new(error_output)
      end

      @logger.debug("Program process exited with status #{exit_status} (output length #{output&.size})")
      if output && @truncate_output
        output = truncate_output(output, [(1.8 * expected_output.size).to_i, MAX_OUTPUT_LENGTH].max)
      end

      status ||=
        if exit_status.signaled? || exit_status.termsig
          :error
        elsif ProgramOutputMatcher.match?(expected_output, output, @program.problem_id)
          :pass
        elsif exit_status.exitstatus != 0 && error_output
          @logger.error("error output and epipe") if epipe
          :error
        else
          @logger.error("fail output and epipe") if epipe
          :fail
        end

      if error_output
        error_output = truncate_output(error_output.gsub('/tmp/', ''), MAX_ERROR_OUTPUT_LENGTH)
      end

      if (@program.bug_version == :fixed && status != :pass) ||
          (!@program.bug_version == :buggy && status == :pass)
        @logger.debug("Run status does not match program status: #{program_specifier} #{status}")
      end

      run = Run.new(
        status:,
        bug_id: @program.bug_id,
        bug_version: @program.bug_version,
        bug_variant: @program.bug_variant,
        test_id: test.id, # use DB id !!!
        error_output:,
        trace_output: capture_result.trace_output,
        output:,
        expected_output:,
        wall_time: capture_result.wall_time
      )


      call_after_run_callback(@program, test, run)

      run
    end

    def compile_and_run
      attributes =
        begin
          compile do |filename, context|
            @logger.debug "Compiling program #{program_specifier} done"
            begin
              run_all_tests(filename, context)
            # rescue Errno::EPIPE, IOError => e
            #   @logger.warn "Received EPIPE/IOError, repeating execution (#{e})"
            #   retry
            end
          end
        rescue CompilationError => e
          error_output = e.message.encode('UTF-8', invalid: :replace, replace: '')
          [Run.new(
            status: :compilation_error,
            bug_id: @program.bug_id,
            bug_version: @program.bug_version,
            bug_variant: @program.bug_variant,
            test_id: @tests.first.id, # use DB id !!!
            error_output:,
            wall_time: nil,
            output: nil
          )]
        rescue Errno::ENOENT => e
          raise "errnoent bug #{@program.bug_id}"
        end

      attributes
    end
  end
end