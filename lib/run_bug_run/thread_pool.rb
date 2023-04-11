require 'thread'

module RunBugRun
  class ThreadPool
    def initialize(size: 5)
      @queue = Queue.new
      @threads = Array.new(size) do
        Thread.new do
          while (task = @queue.deq)
            task.call
          end
        end
      end
    end

    def start!
      @queue.close
      @threads.map(&:join)
    end

    def stop!
      @queue.clear
    end

    def post(&task)
      @queue.enq task
    end
  end
end