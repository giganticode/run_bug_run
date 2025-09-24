require 'logger'
require 'json'

# require 'run_bug_run/dataset'
require 'run_bug_run/json_utils'
require 'run_bug_run/thread_pool'
require 'run_bug_run/test_worker_pool'
require 'run_bug_run/test_runner'
require 'run_bug_run/logger'
require 'run_bug_run/test_run'
require 'run_bug_run/evaluation'
require 'run_bug_run/run'

module RunBugRun
  class Evaluator
    # class TestCache
    #   def initialize(logger, max_size: 10)
    #     @cache = {}
    #     @max_size = max_size
    #     @mutex = Mutex.new
    #     @keys = []
    #     @logger = logger
    #   end

    #   def fetch(problem_id)
    #     @mutex.synchronize do
    #       @cache.fetch(problem_id) do 
    #         if @keys.size > @max_size
    #           expire_key = @keys.shift
    #           @cache.delete expire_key
    #         end

    #         @keys << problem_id
    #         @cache[problem_id] = RunBugRun::Test.where(problem_id:).map(&:to_test_runner_test)
    #       end
    #     end
    #   end
    # end

    attr_reader :evaluated_bug_count
    attr_reader :unevaluated_bug_count
    attr_reader :total_bug_count

    NOT_ALREADY_EVALUATED_SQL = <<~SQL
      NOT EXISTS (
        SELECT 1 FROM runs
        WHERE runs.bug_id = bugs.id 
        AND runs.evaluation_id = :evaluation_id
        AND runs.bug_version = :bug_version
        AND runs.bug_variant = :bug_variant
      )
    SQL

    def initialize(evaluation, bugs, bug_version:, bug_variant: nil, logger:, skip_bad_bugs: true, ignore_existing_run: false)
      # raise ArgumentError, "passed evaluation has not been presisted" unless evaluation.persisted?
      check_bug_version!(bug_version)

      @bug_version = bug_version.to_sym
      @bug_variant = bug_variant
      @total_bug_count = bugs.count

      problems_with_tests = Test.active.select('DISTINCT problem_id')
      @bugs = bugs.includes(:active_tests).references(:active_tests).where(problem_id: problems_with_tests)

      unless ignore_existing_run
        existing_run = Run.where(evaluation: evaluation, bug_version:).where('bug_id = bugs.id AND test_id = tests.id').select(1)
        existing_run = existing_run.where(bug_variant:) if bug_variant
        @bugs = @bugs.where('NOT EXISTS(:existing_run)', existing_run:)
      end

      if skip_bad_bugs
        timed_out_run = Run.where(evaluation: evaluation, bug_version:)
                                       .where('bug_id = bugs.id AND status IN (?)', RunBugRun::Bug::STATUSES.values_at(:timeout, :compilation_error)).select(1)
        timed_out_run = timed_out_run.where(bug_variant:) if bug_variant
        @bugs = @bugs.where('NOT EXISTS(:timed_out_run)', timed_out_run:)
      end

      puts @bugs.to_sql

      @logger = logger
      @evaluation = evaluation
      # @evaluation = evaluation
      # @test_cache = TestCache.new @logger
      @counter = 0
      @unsaved_runs = []
      @unevaluated_bug_count = @bugs.size
      @evaluated_bug_count = @total_bug_count - @unevaluated_bug_count
    end

    def size = @unevaluated_bug_count

    def select_bugs_with_results(results)
      @bugs.select { results.any_for_bug?(_1) }
    end

    def bug_ids
      @bugs.keys
    end

    def evaluate!(candidates: nil, abort_on_timeout: 1, abort_on_fail: 1,
                  abort_on_error: 1, stop_after_first_pass: true, workers: 8)
      bugs = @bugs

      progress_proc = proc do |bug_index|
        (@evaluated_bug_count + bug_index.to_f + 0.5) / @total_bug_count
      end

      evaluate_bugs(bugs, nil, candidates, abort_on_timeout:, abort_on_fail:,
                    abort_on_error:, stop_after_first_pass:, progress_proc:, workers:)
    end

    def inspect
      "#<#{self.class.name} size=#{@unevaluated_bug_count}>"
    end

    private

    module Emojis
      CHECK = "\u{2705}".freeze
      SKULL = "\u{1F480}".freeze
      RED_CROSS = "\u{274C}".freeze
      STOP_WATCH = "\u{23F1}".freeze
      QUESTION_MARK = "\u{003F}".freeze
      HAMMER_AND_WRENCH = "\u{1F6E0}\u{FE0F}".freeze
    end

    RESULT_EMOJIS = {
      pass: Emojis::CHECK,
      fail: Emojis::RED_CROSS,
      error: Emojis::SKULL,
      timeout: Emojis::STOP_WATCH,
      compilation_error: Emojis::HAMMER_AND_WRENCH
    }.tap { _1.default = Emojis::QUESTION_MARK }.with_indifferent_access.freeze

    # def load_tests(problem_id)
    #   @test_cache.fetch(problem_id)
    # end

    def check_bug_version!(bug_version)
      unless Bug::VERSIONS.key?(bug_version)
        raise ArgumentError, "invalid bug version (#{bug_version})"
      end
    end

    def upsert_unsaved_runs
      if @unsaved_runs.any?
        @logger.info("Saving...")
        Run.upsert_all(@unsaved_runs, unique_by: %i[bug_id test_id candidate_index evaluation_id bug_version bug_variant])
        @unsaved_runs.clear
      end
    end

    def save_candidate_runs(candidate_runs)
      evaluation_id = @evaluation.id
      unsaved_runs = []

      candidate_runs.each_with_index do |runs, candidate_index|
        runs.each do |run|
          # equal to expected test output, no point in saving!?
          output = run.pass? ? nil : run.output

          unsaved_runs << {
            evaluation_id:,
            candidate_index:,
            status: RunBugRun::Bug::STATUSES.fetch(run.status),
            bug_id: run.bug_id,
            bug_version: RunBugRun::Bug::VERSIONS.fetch(run.bug_version),
            bug_variant: RunBugRun::Bug::VARIANTS.fetch(run.bug_variant, :default),
            test_id: run.test_id,
            wall_time: run.wall_time,
            output:,
            error_output: run.error_output
          }
        end
      end

      @unsaved_runs.concat unsaved_runs
      if @unsaved_runs.size > 1024
        upsert_unsaved_runs
        true
      else
        false
      end
    end

    def evaluate_bugs(bugs, tests, candidates,
                      workers:,
                      abort_on_timeout: 1, abort_on_fail: 1, abort_on_error: 1,
                      stop_after_first_pass: true,
                      progress_proc: nil)
      test_worker_pool = TestWorkerPool.new logger: @logger, size: workers
      pool_mutex = Mutex.new
      pool = ThreadPool.new size: workers

      candidates = candidates.with_variant(@bug_variant) if @bug_variant
      tests_per_problem = Test.active.group(:problem_id).count

      last_submit_ts = Time.now

      bugs.find_each.with_index do |bug, bug_index|
        pool.post do
          #problem_tests = load_tests(bug.problem_id)
          problem_tests = bug.test_runner_tests
          progress = progress_proc&.call bug_index

          begin
            candidate_runs =
              case @bug_version
              when :fixed, :buggy
                program = bug.to_program @bug_version

                now = Time.now
                last_submit_ts = now
                runs, worker_info = test_worker_pool.submit(program, problem_tests,
                                                            abort_on_timeout:,
                                                            abort_on_error:,
                                                            abort_on_fail:)

                [runs]
              when :candidate  
                candidate_programs = candidates[bug.id]
                if candidate_programs.nil?
                  []
                else
                  candidate_programs.each_with_object([]) do |candidate_program, acc|
                    runs, worker_info = test_worker_pool.submit(candidate_program, problem_tests,
                                                                abort_on_timeout:,
                                                                abort_on_error:,
                                                                abort_on_fail:)
                    acc << runs
                    break acc if stop_after_first_pass && runs.all?(&:pass?)
                  end
                end
              else
                raise RuntimeError, "invalid bug version (#{bug_version})"
              end
            pool_mutex.synchronize do
              @counter += 1
              save_candidate_runs candidate_runs
            end
            max_run = candidate_runs.max_by { |runs| runs.count(&:pass?) }
            language = Bug::LANGUAGE_NAMES.fetch(bug.language)
            progress_str = format('[%4.1f%%]', progress * 100)
            if max_run
              # passed = max_run.all? { _1.fetch(:result) == 'pass' }
              emoji_str = max_run.map do
                            RESULT_EMOJIS[_1.status]
                          end.tally.map { format("%3d\u{00d7}%s", _2, _1) }.join(' ')
              @logger.info("#{progress_str} [Worker#{worker_info[:worker_id]}] Bug #{format('%6d',
                                                                                            bug.id)} (#{language}): #{emoji_str} #{max_run.size}/#{tests_per_problem.fetch(bug.problem_id, 0)}")
            else
              @logger.info("#{progress_str} Bug #{format('%5d', bug.id)} (#{language}): no prediction found")
            end
          rescue TestRunner::BWrapError => e
            @logger.error e
          end
        end
      end

      pool.join
      test_worker_pool.shutdown

      # flush
      upsert_unsaved_runs

      true
    end

    class << self
      def load(filenames, split: nil, languages: nil, bug_version: nil)
        filenames = Array(filenames)
        languages = filenames.map do |filename|
          if (match = filename.match(/(c|cpp|javascript|java|ruby|python|php|go)_/))
            match[1].to_sym
          else
            raise ArgumentError, "invalid submissions filename '#{filename}'"
          end
        end

        logger = Logger.new
        bugs = {}

        filenames.zip(languages) do |filename, language|
          JSONUtils.read(filename).each do |hash|
            problem_id = hash.fetch(:problem_id).to_sym

            buggy_submission = Submission.new(
              id: hash.fetch(:buggy_submission_id),
              code: hash.fetch(:buggy_code),
              main_class: hash[:buggy_main_class],
              accepted: false,
              problem_id:,
              language:,
              errors: hash[:errors]
            )

            fixed_submission = Submission.new(
              id: hash.fetch(:fixed_submission_id),
              code: hash.fetch(:fixed_code),
              main_class: hash[:fixed_main_class],
              accepted: true,
              problem_id:,
              language:,
              errors: hash[:errors]
            )

            bug = Bug.new(
              id: hash.fetch(:id),
              language:,
              problem_id:,
              user_id: hash.fetch(:user_id).to_sym,
              labels: hash.fetch(:labels),
              change_count: hash.fetch(:change_count),
              line_hunks: hash.fetch(:line_hunks),
              buggy_submission:,
              fixed_submission:
            )

            raise 'duplicate bug' if bugs.key? bug.id

            bugs[bug.id] = bug
          end
        end

        new bugs, logger:
      end
    end
  end
end
