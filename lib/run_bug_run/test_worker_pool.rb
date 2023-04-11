require 'open3'
require 'stringio'
require 'io/wait'
require 'json'

require 'run_bug_run/bug'
require 'run_bug_run/test'
require 'run_bug_run/test_worker'

module RunBugRun
  class TestWorkerPool
    SANDBOX_HOME = '/home/sandbox'.freeze

    class Connection
      attr_reader :id, :pid, :read_io, :write_io

      def initialize(id, pid, read_io, write_io, logger)
        @id = id
        @pid = pid
        @read_io = read_io
        @write_io = write_io
        @logger = logger
        @mutex = Mutex.new
      end

      def idle?
        !@mutex.locked?
      end

      def submit(str)
        @mutex.synchronize do
          s = Time.now
          @logger.debug("Sumitting '#{str}'")
          @logger.debug("Writing '#{TestWorker::HEADER}'")
          @write_io.write(TestWorker::HEADER)
          @logger.debug("Writing '#{str.bytesize}'")
          @write_io.write([str.bytesize].pack('q'))
          @write_io.write(str)
          @write_io.flush

          recv_header = @read_io.read(TestWorker::HEADER.bytesize)
          @logger.debug("Reading '#{recv_header}'")
          raise "expected header but got #{recv_header}" if recv_header != TestWorker::HEADER

          size = @read_io.read(8).unpack1('q')
          @logger.debug("Reading '#{size}'")
          result = @read_io.read(size)
          @logger.debug("Reading '#{result}'")
          @logger.debug("Submit took #{Time.now - s} seconds")
          result
        end
      end

      def shutdown
        @read_io.close
        @write_io.close
      end
    end

    def initialize(size:, logger: nil)
      @logger = logger || ::Logger.new($stdout)
      @queue = Queue.new
      @connections = size.times.map do |worker_index|
        child_read, parent_write = IO.pipe
        parent_read, child_write = IO.pipe

        child_read.binmode
        parent_write.binmode
        parent_read.binmode
        child_write.binmode

        pid = spawn_worker(worker_index, child_read, child_write)
        connection = Connection.new(worker_index, pid, parent_read, parent_write, @logger)
        @queue.enq connection
        connection
      end
    end

    def submit(submission, io_samples, **options)
      connection = @queue.deq
      result_str = connection.submit(JSON.generate([submission.to_h, io_samples.map(&:to_h), options.to_h]))
      result = JSON.parse(result_str, symbolize_names: true)
      @queue.enq connection
      [result, { worker_id: connection.id }]
    end

    def shutdown
      @connections.each(&:shutdown)
    end

    private

    def to_sandbox_path(path)
      path.sub(Dir.home, SANDBOX_HOME)
    end

    def run_worker_code(id)
      <<~RUBY
        require 'run_bug_run/test_worker'
        RunBugRun::TestWorker.new(id: #{id}, read_fd: 3, write_fd: 4).run!
      RUBY
    end

    def spawn_worker(id, child_read, child_write)
      ruby_bindir = RbConfig::CONFIG['bindir']
      ruby_path = RbConfig::CONFIG.values_at('bindir', 'libexecdir').join(':')
      ruby_prefix = RbConfig::CONFIG['prefix']
      rubylib = ($LOAD_PATH + [File.join(RunBugRun.root, 'lib')]).map { to_sandbox_path(_1) }.join(':')

      cmd = [
        'bwrap',
        '--ro-bind', '/usr', '/usr',
        '--ro-bind', '/etc/alternatives', '/etc/alternatives',
        '--ro-bind', ruby_prefix, to_sandbox_path(ruby_prefix),
        '--ro-bind', RunBugRun.root, to_sandbox_path(RunBugRun.root),
        '--dir', '/tmp',
        '--dir', '/var',
        '--symlink', '../tmp', 'var/tmp',
        '--proc', '/proc',
        '--dev', '/dev',
        '--symlink', 'usr/lib', '/lib',
        '--symlink', 'usr/lib64', '/lib64',
        '--symlink', 'usr/bin', '/bin',
        '--symlink', 'usr/sbin', '/sbin',
        '--chdir', '/tmp',
        '--unshare-all',
        '--new-session',
        '--die-with-parent',
        '--clearenv',
        '--setenv', 'RUBYLIB', rubylib,
        '--setenv', 'LD_LIBRARY_PATH', to_sandbox_path(RbConfig::CONFIG['libdir']),
        '--setenv', 'PATH', "#{ruby_path}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
      ]
      ruby_path = File.join(to_sandbox_path(ruby_bindir), 'ruby')
      spawn(*cmd, ruby_path, '-e', run_worker_code(id), 3 => child_read,
                                                        4 => child_write, close_others: true)
    end
  end
end
