require 'run_bug_run/dataset'

module RunBugRun
  class Tests
    def [](problem_id)
      @tests.fetch(problem_id)
    end

    def initialize(tests)
      @tests = tests
    end

    def inspect
      to_s
    end

    class << self
      def load(filename)
        tests = Hash.new { |h, k| h[k] = [] }
        JSONUtils.load_file(filename).each do |hash|
          test = Test.new(
            id: hash.fetch(:id),
            input: hash.fetch(:input),
            output: hash.fetch(:output)
          )
          tests[hash[:problem_id].to_sym] << test
        end

        new tests
      end

      private :new
    end
  end
end