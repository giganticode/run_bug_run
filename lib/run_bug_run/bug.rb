module RunBugRun
  class Bug
    attr_reader :id, :language, :problem_id, :user_id, :buggy_submission,
                :fixed_submission, :labels, :change_count, :line_hunks

    def initialize(id:, language:, problem_id:, user_id:, labels:, buggy_submission:, fixed_submission:, change_count:, line_hunks:)
      @id = id
      @language = language
      @problem_id = problem_id
      @user_id = user_id
      @labels = labels
      @buggy_submission = buggy_submission
      @fixed_submission = fixed_submission
      @change_count = change_count
      @line_hunks = line_hunks
    end

    def inspect
      "#<#{self.class.name} id=#{@id} language=#{@language} problem_id=#{@problem_id}>"
    end

    def diff(before_name, after_name)
      require 'diffy'

      before = submission before_name
      after = submission after_name
      Diffy::Diff.new(before.code, after.code).to_s(:color)
    end

    def submission(version)
      case version
      when :buggy
        buggy_submission
      when :fixed
        fixed_submission
      else
        nil
      end
    end
  end
end