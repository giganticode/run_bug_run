require 'open3'
require 'stringio'
require 'io/wait'
require 'logger'
require 'json'

require 'run_bug_run'
require 'run_bug_run/bug'
require 'run_bug_run/test'
require 'run_bug_run/program'
require 'run_bug_run/test_runner'
require 'run_bug_run/sandboxing'

module RunBugRun
  class TestWorker

    HEADER = 'BUGS'.freeze
    TRACE_FD = 3


    # class TestCache
    #   def initialize(max_size: 10)
    #     @cache = {}
    #     @max_size = max_size
    #     @mutex = Mutex.new
    #     @keys = []
    #   end

    #   def fetch(problem_id)
    #     @mutex.synchronize do
    #       @cache.fetch(problem_id) do 
    #         if @keys.size > @max_size
    #           expire_key = @keys.shift
    #           @cache.delete expire_key
    #         end

    #         @keys << problem_id

    #         @cache[problem_id] = RunBugRun::Test.where(problem_id:).to_a
    #       end
    #     end
    #   end
    # end

    def initialize(id:, read_fd:, write_fd:, database_path:, logger_level: Logger::INFO)
      @id = id
      @read_io = IO.for_fd read_fd
      @write_io = IO.for_fd write_fd

      @logger = ::Logger.new $stdout
      @logger.level = logger_level
      @logger.formatter = proc do |severity, datetime, _progname, msg|
        date_format = datetime.strftime("%Y-%m-%d %H:%M:%S")
        sprintf "[Worker#%d] [%s] %-5s: %s\n", id, date_format, severity, msg
      end

      Sandboxing.check_in_sandbox!(network_check: true)
      @logger.debug("Sandbox check passed...")
      # @test_cache = TestCache.new max_size: 5
      # ActiveRecord::Base.establish_connection(adapter: :sqlite3, database: database_path)
    end

    def to_sandbox_path(path)
      path.sub(Dir.home, SANDBOX_HOME)
    end

    # def load_tests(problem_id)
    #   @test_cache.fetch(problem_id)
    # end

    def run!
      loop do
        @read_io.wait_readable
        header = @read_io.read(HEADER.bytesize)

        # EOF
        break if header.nil?

        raise "expected header but got #{header.inspect}" if header != TestWorker::HEADER

        size = @read_io.read(8).unpack1('q')
        @logger.debug { "Read size: #{size}" }
        input_str = @read_io.read(size)
        input = Marshal.load(input_str)
        # @logger.debug("Read: #{input.inspect}")

        # program = Program.new(**input[0])
        program = input[0]
        tests = input[1]
        # tests = load_tests(program.problem_id)
        options = input[2] #.transform_keys(&:to_sym)

        @logger.debug { "Running submission #{program} on #{tests.map(&:id)}" }

        s = Time.now
        runner = TestRunner.new(program, tests, logger: @logger, **options)
        results = runner.run!
        elapsed_time = Time.now - s
        @logger.info { "running #{tests.size} tests took #{elapsed_time.round(1)} seconds (#{(elapsed_time / tests.size).round(2)} per test)" }

        # result_payload = results.to_json
        t0 = Time.now
        results_payload = Marshal.dump(results)
        @write_io.write(HEADER)
        @write_io.write([results_payload.bytesize].pack('q'))
        @write_io.write(results_payload)
        @write_io.flush
        t1 = Time.now

        # sleep 10
      end
    end
  end
end