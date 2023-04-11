require 'run_bug_run/json_utils'

module RunBugRun
  class CandidateSubmissions
    include Enumerable

    def initialize(candidate_submissions)
      @candidate_submissions = candidate_submissions
    end

    def each(...) = @candidate_submissions.each_value(...)

    def [](bug_id)
      @candidate_submissions[bug_id.to_i]
    end

    class << self
      def load(filename, bugs)
        candidate_submissions = JSONUtils.load_file(filename).each_with_object({}) do |row, hash|
          bug_id = row.fetch(:id).to_i

          bug = bugs[bug_id]
          if bug.nil?
            RunBugRun.logger.warn("Candidate submission for unknown bug #{bug_id}")
            next
          end

          preds = row.fetch(:preds)
          candidates =
            case preds
            when Hash
              preds.transform_values do |variant_preds|
                build_submissions(bug, variant_preds)
              end
            when Array
              build_submissions(bug, preds)
            end

          hash[bug_id] = candidates
        end
        new candidate_submissions
      end

      private

      def build_submissions(bug, candidate_codes)
        candidate_codes.map do |candidate_code|
          Submission.new(
            id: bug.buggy_submission.id,
            code: candidate_code,
            main_class: bug.fixed_submission.main_class,
            accepted: true,
            problem_id: bug.problem_id,
            language: bug.language
          )
        end
      end

    end
  end
end
