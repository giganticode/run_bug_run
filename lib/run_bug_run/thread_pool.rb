require 'thread'

module RunBugRun
  class ThreadPool
    def initialize(size: 5, queue_size: 1024)
      @queue = Thread::SizedQueue.new queue_size
      @threads = Array.new(size) do
        Thread.new do
          while (task = @queue.deq)
            begin
              task.call
            rescue StandardError => e
              puts e
              puts e.backtrace
            end
          end
        end
      end
      @threads.each_with_index { _1.name = "PoolThread##{_2}" }
    end

    def join
      # worker threads stop if they pop nil from the queue
      size.times { @queue.enq nil }
      @queue.close
      @threads.map(&:join)
    end

    def post(&task)
      @queue.enq task
    end
  end
end
