require 'logger'

module RunBugRun
  class Logger < ::Logger
    attr_reader :progress

    class Formatter
      def initialize(logger)
        @logger = logger
      end
    end

    def initialize
      super($stdout)
      @progress = 0.0
      self.formatter = proc do |severity, datetime, progname, msg|
        date_format = datetime.strftime("%Y-%m-%d %H:%M:%S")
        sprintf "[%s] %-5s: %s\n", date_format, severity, msg
      end
    end
  end
end

