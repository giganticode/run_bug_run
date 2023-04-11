module RunBugRun
  class EvaluationResults
    attr_reader :bugs, :tests, :only_plausible, :candidate_limit

    def initialize(results_hash, bugs, tests, only_plausible: false, candidate_limit: nil)
      raise ArgumentError, "expect hash as first argument" unless results_hash.is_a?(Hash)

      @only_plausible = only_plausible
      @candidate_limit = candidate_limit
      @results_hash = results_hash
      @bugs = bugs
      @tests = tests
    end

    def dup
      self.class.new(@results_hash.dup, @bugs, @tests, only_plausible:, candidate_limit:)
    end

    def size = @results_hash.size

    def candidates_per_bug
      _, first_candidate_runs = @results_hash.first
      first_candidate_runs.size
    end

    def to_hash
      @results_hash
    end

    def empty?
      @results_hash.empty?
    end

    def group_by_language
      wrap_values(@results_hash.group_by { |bug_id, _candidate_results| @bugs[bug_id]&.language })
    end

    def inspect
      "#<#{self.class.name} size=#{@results_hash.size}>"
    end

    def trim_to_bugs
      results_hash = @results_hash.select { |bug_id, _| @bugs.key? bug_id }.to_h
      self.class.new(results_hash, @bugs, @tests, only_plausible:, candidate_limit:)
    end

    def filter_languages(languages)
      results_hash = @results_hash.select do |bug_id, _candidate_runs|
        bug = @bugs[bug_id]
        languages.include?(bug.language)
      end.to_h
      self.class.new(results_hash, @bugs, @tests, only_plausible:, candidate_limit:)
    end

    def group_by_exception
      by_exception_map = Hash.new { |h, k| h[k] = {} }
      no_exceptions = {}
      @results_hash.each do |bug_id, candidate_results|
        bug = @bugs[bug_id]
        exceptions = bug&.buggy_submission&.errors&.flat_map { _1[:exception] }
        if exceptions.nil? || exceptions.empty?
          no_exceptions[bug_id] = candidate_results
        else
          exceptions&.uniq!
          exceptions&.compact!
          exceptions&.each do |exception|
            by_exception_map[exception][bug_id] = candidate_results
          end
        end
      end
      by_exception_map[nil] = no_exceptions
      wrap_values!(by_exception_map)
      by_exception_map
    end

    def group_by_change_count
      wrap_values(@results_hash.group_by { |bug_id, _candidate_results| @bugs[bug_id]&.change_count })
    end

    def each_bug(&)
      @results_hash.each_key.lazy.map { |bug_id| @bugs[bug_id] }.each(&)
    end

    def any_for_bug?(bug_or_bug_id)
      key =
        case bug_or_bug_id
        when Integer
          bug_or_bug_id.to_s
        when RunBugRun::Bug
          bug_or_bug_id.id.to_s
        else
          raise ArgumentError, 'must pass bug or bug id'
        end

      @results_hash[key]&.any?
    end

    def plausible_count
      if @only_plausible
        size
      else
        @results_hash.count do |bug_id, candidate_results|
          plausible_candidate?(bug_id, candidate_results)
        end
      end
    end

    def where_any_plausible_candidate
      if @only_plausible
        dup
      else
        filtered_results_hash = @results_hash.select do |bug_id, candidate_results|
          plausible_candidate?(bug_id, candidate_results)
        end

        self.class.new(filtered_results_hash, @bugs, @tests, only_plausible: false, candidate_limit:)
      end
    end

    private

    def plausible_candidate?(bug_id, candidate_results)
      bug = @bugs[bug_id]
      test_count = tests[bug.problem_id].size
      candidate_results_enum =
        if @candidate_limit
          candidate_results.lazy.take(@candidate_limit)
        else
          candidate_results
        end
      candidate_results_enum.any? do |candidate_test_runs|
        passed_count = candidate_test_runs.count { _1.fetch('result') == 'pass' }
        passed_count == test_count
      end
    end

    def wrap_values(groups_hash)
      groups_hash.transform_values do |group_results_hash|
        self.class.new(group_results_hash.to_h, @bugs, @tests, only_plausible:, candidate_limit:)
      end
    end

    def wrap_values!(groups_hash)
      groups_hash.transform_values! do |group_results_hash|
        self.class.new(group_results_hash.to_h, @bugs, @tests, only_plausible:, candidate_limit:)
      end
    end

    EMPTY = new({}, nil, nil, only_plausible: false)
  end
end
