require 'run_bug_run/json_utils'
require 'run_bug_run/program'

module RunBugRun
  class FixCandidates
    include Enumerable

    def initialize(fix_candidates)
      @fix_candidates = fix_candidates
    end

    def each(...) = @fix_candidates.each_value(...)

    def [](bug_id)
      @fix_candidates[bug_id.to_i]
    end

    def with_variant(variant)
      FixCandidates.new(@fix_candidates.each_with_object({}) { |c, h| h[c.bug_id] = c if c.variant == variant })
    end

    class << self
      def load(filename)
        # bug_ids = Bug.pluck(:id).to_set
        batch_size = 10_000
        fix_candidates = []

        exact_match_count = 0

        JSONUtils.read(filename).each_slice(batch_size) do |batch|
          bug_ids = batch.map { _1.fetch(:id).to_i }
          bugs = Bug.where(id: bug_ids).select(:id, :fixed_main_class, :language, :problem_id, :fixed_code).index_by(&:id)

          batch.each do |row|
            bug_id = row.fetch(:id).to_i
            bug = bugs[bug_id]

            if bug.nil?
              RunBugRun.logger.warn("Candidate fix for unknown bug #{bug_id}")
              next
            end

            preds = row.fetch(:preds)
            programs =
              case preds
              when Hash
                preds.map do |variant, variant_preds|
                  build_programs(bug, variant_preds, variant)
                end
              when Array
                build_programs(bug, preds, :default)
              end
            
            if programs.any? { normalize_whitespace(_1.code) == normalize_whitespace(bug.fixed_code)}
              exact_match_count += 1
            end

            fix_candidates.concat programs
          end
        end
        
        # FIXME: make this stable, such that the order of elements in preds in preserved!

        # sort by problem_id to maximize test cache use (tests are per problem_id)
        puts "Exact match count #{exact_match_count}"
        new fix_candidates.sort_by(&:problem_id).group_by(&:bug_id)
      end

      private

      def normalize_whitespace(str)
        str.gsub(/\s+/, ' ')
      end


      def build_programs(bug, candidate_codes, bug_variant)
        candidate_codes.map do |candidate_code|
          Program.new(
            code: candidate_code,
            bug_id: bug.id,
            bug_variant: bug_variant,
            bug_version: :candidate,
            main_class: bug.fixed_main_class,
            language: bug.language,
            problem_id: bug.problem_id
          )
        end
      end

    end
  end
end
