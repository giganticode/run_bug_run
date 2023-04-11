require 'open3'
require 'logger'
require 'io/wait'
require 'tmpdir'
require 'tempfile'

require 'run_bug_run/submission_output_matcher'

module RunBugRun
  class TestRunner
    # largest test output is 1098
    MAX_OUTPUT_LENGTH = 1024 * 2
    MAX_ERROR_OUTPUT_LENGTH = 1024 * 4
    NO_RLIMIT_LANGUAGES = %i[java javascript go].freeze
    JAVA_CLASS_REGEX = /^\s*(?:(?:public|static|protected|private|final)\s+)*class\s+([a-zA-Z0-9_]+)/

    DEFAULT_TIMEOUT = 5

    def initialize(submission, tests, abort_on_timeout: false, abort_on_fail: false,
                  abort_on_error: false, truncate_output: true, logger_level: Logger::WARN, logger: nil)
      @truncate_output = truncate_output
      @submission = submission
      @submission_language = @submission.language.to_sym
      @tests = tests
      @abort_on_timeout = abort_on_timeout
      @abort_on_fail = abort_on_fail
      @abort_on_error = abort_on_error

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

      @logger.debug "Running #{@submission.id} on #{@tests.map(&:id)}"
      return [] if @tests.empty?
      compile_and_run
    end

    def aborted? = @aborted

    class CompilationError < StandardError; end
    class BWrapError < StandardError; end

    private

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
      code = @submission.code.sub(/package\s+([a-zA-Z0-9_.]+)\s*;/, '')
      class_name = @submission.main_class
      # class_names = code.scan(JAVA_CLASS_REGEX).flatten
      # class_name = class_names.first if class_names.size == 1
      # class_name ||= find_java_main_class(@submission)
      raise CompilationError, 'missing main class' if class_name.nil?

      run_compiler(['javac', '-encoding', 'UTF-8'], "#{class_name}.java", code) do |tmp_dir|
        class_filenames = Dir[File.join(tmp_dir, '*.class')]
        # sandbox_filenames = class_filenames.map { File.join('/tmp', File.basename(_1)) }
        block[class_filenames, { class_name: class_name }]
      end
    end

    def compile_c(cc, ext, &block)
      run_compiler(cc, "file.#{ext}", @submission.code, '-lm') do |tmp_dir|
        block[File.join(tmp_dir, 'a.out'), {}]
      end
    end

    def compile_go(&block)
      run_compiler(['go', 'build', '-o', 'a.out'], 'file.go', @submission.code, env: {'GOCACHE' => '/tmp/'} ) do |tmp_dir|
        block[File.join(tmp_dir, 'a.out'), {}]
      end
    end

    def dummy_compile(&block)
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          file_path = File.join(dir, "file.#{@submission.filename_ext}")
          File.write(file_path, @submission.code)
          block[file_path, {}]
        end
      end
    end

    def compile(&block)
      case @submission_language
      when :java
        compile_java(&block)
      when :cpp
        compile_c('g++', 'cpp', &block)
      when :c
        compile_c('gcc', 'c', &block)
      when :go
        compile_go(&block)
      else
        dummy_compile(&block)
      end
    end

    def cmd(filename, context)
      case @submission_language
      when :ruby
        ['/usr/bin/ruby', '--disable-gems', filename]
      when :python
        ['/usr/bin/python3', filename]
      when :php
        ['/usr/bin/php7.4', filename]
      when :javascript
        ['/usr/bin/node', '--max-old-space-size=512', filename]
      when :c, :cpp, :go
        ['./a.out']
      when :java
        ['/usr/bin/java', '-mx512m', '-XX:TieredStopAtLevel=1', context.fetch(:class_name)]
        # cmd << '/usr/lib/jvm/java-17-openjdk-amd64/bin/java' <<
      else
        raise "language #{@submission_language} is not supported"
      end
    end

    def abort?(result_type, abort_count, result1, result2=result1)
      if abort_count && (result_type == result1 || result_type == result2)
        @counters[result1] += 1
        if abort_count == true || @counters.fetch(result1) >= abort_count
          @logger.debug "#{@counters.fetch(result1)} #{result1}s...aborting"
          return true
        end
      end
      false
    end

    def run_all_tests(filename, context)
      @tests.each_with_object([]) do |test, results|
        result = run_test(filename, context, test)
        if result
          result_type = result.fetch(:result)
          results << result

          return results if abort?(result_type, @abort_on_timeout, :timeout, :timeout2) ||
                            abort?(result_type, @abort_on_fail, :fail) ||
                            abort?(result_type, @abort_on_error, :error)
        end
      end
    end

    def read_with_timeout(io, timeout)
      buf = StringIO.new
      start_time = Time.now

      loop do
        return :timeout if Time.now - start_time >= timeout

        read_result = io.read_nonblock(512, exception: false)
        if read_result == :wait_readable
          select_result = IO.select([io], nil, nil, 0.1)
          next if select_result # there is something to read, restart loop
        elsif read_result.nil?
          # eof, done reading
          break
        else
          buf.write read_result
        end
      end
      buf.string
    end

    def capture3_with_timeout(cmd, env: {}, timeout: DEFAULT_TIMEOUT, stdin_data: '', binmode: false, **opts)
      Open3.popen3(env, *cmd, opts) {|i, o, e, t|
        if binmode
          i.binmode
          o.binmode
          e.binmode
        end
        out_reader = Thread.new do
          read_with_timeout o, timeout
        end
        err_reader = Thread.new do
          read_with_timeout e, timeout
        end

        epipe = false

        begin
          i.write stdin_data
          # some inputs lack final newline
          i.write "\n" unless stdin_data.end_with?("\n")
        rescue Errno::EPIPE
          epipe = true
        end

        begin
          i.close
        rescue Errno::EPIPE
          epipe = true
        end

        out_value = out_reader.value
        err_value = err_reader.value

        if out_value == :timeout || err_value == :timeout
          begin
            Process.kill 'KILL', t.pid
          rescue Errno::ESRCH
            @logger.info "pid was no longer alive"
          end
        end
        [out_value, err_value, t.value, epipe]
      }
    end

    def run_test(filename, context, test)
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

      result = nil

      # Limit causes JVM to crash. We can limit memory using JVM anyway
      popen_opts[:rlimit_as] = 512 * 1024 * 1024 unless NO_RLIMIT_LANGUAGES.include?(@submission_language)

      @logger.debug("Running submission #{@submission.id} on test #{test.id}")

      output, error_output, exit_status, epipe = capture3_with_timeout(cmd, env: env, stdin_data: test_input, **popen_opts)

      if output == :timeout || error_output == :timeout
        result = :timeout
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

      result ||=
        if exit_status.signaled? || exit_status.termsig
          :error
        elsif SubmissionOutputMatcher.match?(expected_output, output, @submission.problem_id)
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

      if (@submission.accepted? && result != :pass) ||
          (!@submission.accepted? && result == :pass)
        @logger.debug("Run result does not match submission status: #{@submission.id} #{result}")
      end

      {
        result:,
        submission_id: @submission.id,
        test_id: test.id,
        error_output:,
        output:,
        expected_output:,
      }
    end

    def compile_and_run
      attributes =
        begin
          compile do |filename, context|
            @logger.debug "Compiling submission #{@submission.id} done"
            begin
              run_all_tests(filename, context)
            # rescue Errno::EPIPE, IOError => e
            #   @logger.warn "Received EPIPE/IOError, repeating execution (#{e})"
            #   retry
            end
          end
        rescue CompilationError => e
          [{
            result: :compilation_error,
            submission_id: @submission.id,
            test_id: @tests.first.id,
            error_output: e.message,
            output: nil
          }]
        end

      attributes
    end
  end
end