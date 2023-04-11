require 'logger'
require 'json'

require 'run_bug_run/dataset'
require 'run_bug_run/json_utils'
require 'run_bug_run/thread_pool'
require 'run_bug_run/test_worker_pool'
require 'run_bug_run/test_runner'
require 'run_bug_run/logger'

module RunBugRun
  class Bugs
    include Enumerable

    SPLITS = %i[train valid test].freeze
    ALL_LANGUAGES = %i[c cpp go java javascript php python ruby].freeze

    LANGUAGE_NAME_MAP = {
      c: 'C',
      cpp: 'C++',
      javascript: 'JavaScript',
      java: 'Java',
      ruby: 'Ruby',
      python: 'Python',
      php: 'PHP',
      go: 'Go'
    }.freeze

    def each(...) = @bugs.each_value(...)

    def initialize(bugs, logger_level: Logger::INFO, logger: nil)
      case bugs
      when Hash
        @bugs = bugs
      when Array
        @bugs = bugs.each_with_object({}) { |b, o| o[b.id] = b }
      else
        raise ArgumentError, "first parameter must be hash or array"
      end
      @logger = Logger.new || logger
      @logger.level = logger_level
    end

    def size = @bugs.size
    def values_at(...) = @bugs.values_at(...)

    # def restart!(checkpoint)
    #   @logger.warn "Restarting process..."
    #   sleep 60 * 10
    #   Kernel.exec("bundle exec #{$0} #{ARGV.join ' '} --checkpoint #{checkpoint}")
    # end

    def [](bug_id)
      @bugs[bug_id.to_i]
    end

    def key?(bug_id)
      @bugs.key? bug_id.to_i
    end

    def select(...) = self.class.new(@bugs.each_value.select(...), logger: @logger, logger_level: @logger.level)

    def take(count)
      self.class.new(@bugs.take(count).to_h, logger: @logger, logger_level: @logger.level)
    end

    def select_bugs_with_results(results)
      @bugs.select { results.any_for_bug?(_1) }
    end

    def bug_ids
      @bugs.keys
    end

    def evaluate!(tests, candidates: nil, fixed: false, buggy: false, abort_on_timeout: 1, abort_on_fail: 1,
                  abort_on_error: 1, stop_after_first_pass: true, checkpoint: nil, workers: 8, variant: nil)
      if checkpoint
        all_rows = JSONUtils.load_json(checkpoint, compression: :gzip)
        all_rows.transform_keys!(&:to_i)
        bugs = @bugs.reject { |bug_id, _bug| all_rows.key? bug_id }
        @logger.info "Continuing evaluation from checkpoint, #{@bugs.size - bugs.size} bugs already evaluated"
      else
        all_rows = {}
        bugs = @bugs
      end

      progress_proc = proc do |bug_index|
        (all_rows.size + bug_index.to_f + 0.5) / @bugs.size
      end

      eval_rows = evaluate_bugs(bugs, tests, candidates, fixed:, buggy:, abort_on_timeout:, abort_on_fail:,
                                                         abort_on_error:, stop_after_first_pass:, progress_proc:, workers:, variant:)
      all_rows.merge! eval_rows
      all_rows
    end

    def inspect
      "#<#{self.class.name} size=#{@bugs.size}>"
    end

    private

    module Emojis
      CHECK = "\u{2705}".freeze
      SKULL = "\u{1F480}".freeze
      RED_CROSS = "\u{274C}".freeze
      STOP_WATCH = "\u{23F1}".freeze
      QUESTION_MARK = "\u{003F}".freeze
    end

    RESULT_EMOJIS = {
      pass: Emojis::CHECK,
      fail: Emojis::RED_CROSS,
      error: Emojis::SKULL,
      timeout: Emojis::STOP_WATCH
    }.tap { _1.default = Emojis::QUESTION_MARK }.freeze

    def evaluate_bugs(bugs, tests, candidates,
                      fixed:, buggy:, workers:,
                      abort_on_timeout: 1, abort_on_fail: 1, abort_on_error: 1,
                      stop_after_first_pass: true,
                      progress_proc: nil, variant: nil)
      test_worker_pool = TestWorkerPool.new logger: @logger, size: workers
      eval_rows = {}
      eval_rows_mutex = Mutex.new
      pool = ThreadPool.new size: workers

      bugs.each_with_index do |(_bug_id, bug), bug_index|
        pool.post do
          problem_tests = tests[bug.problem_id]
          progress = progress_proc&.call bug_index

          begin
            rows =
              if fixed || buggy
                submission = fixed ? bug.fixed_submission : bug.buggy_submission
                runs, worker_info = test_worker_pool.submit(submission, problem_tests,
                                                            abort_on_timeout:,
                                                            abort_on_error:,
                                                            abort_on_fail:)

                [runs]
              else
                candidate_submissions = candidates[bug.id]
                if candidate_submissions.nil?
                  @logger.warn "No candidates for bug #{bug.id}"
                  []
                else
                  if candidate_submissions.is_a?(Hash)
                    raise ArgumentError, 'multiple variants found but no variant specificied' if variant.nil?

                    candidate_submissions = candidate_submissions[variant]
                    if candidate_submissions.nil?
                      @logger.warn "No candidates for bug #{bug.id} (#{variant})"
                      candidate_submissions = []
                    end
                  end
                  candidate_submissions.each_with_object([]) do |candidate_submission, acc|
                    runs, worker_info = test_worker_pool.submit(candidate_submission, problem_tests,
                                                                abort_on_timeout:,
                                                                abort_on_error:,
                                                                abort_on_fail:)
                    acc << runs
                    break acc if stop_after_first_pass && runs.all? { _1.fetch(:result) == 'pass' }
                  end
                end
              end
            eval_rows_mutex.synchronize do
              eval_rows[bug.id] = rows if rows
            end
            max_run = rows.max_by { |runs| runs.count { _1.fetch(:result) == 'pass' } }
            language = Bugs::LANGUAGE_NAME_MAP.fetch(bug.language)
            progress_str = format('[%2d%%]', (progress * 100).round)
            if max_run
              # passed = max_run.all? { _1.fetch(:result) == 'pass' }
              emoji_str = max_run.map do
                            RESULT_EMOJIS[_1.fetch(:result).to_sym]
                          end.tally.map { format("%3d\u{00d7}%s", _2, _1) }.join(' ')
              @logger.info("#{progress_str} [Worker#{worker_info[:worker_id]}] Bug #{format('%6d',
                                                                                            bug.id)} (#{language}): #{emoji_str} #{max_run.size}/#{problem_tests.size}")
            else
              @logger.info("#{progress_str} Bug #{format('%5d', bug.id)} (#{language}): no prediction found")
            end
          rescue TestRunner::BWrapError => e
            @logger.error e
            pool.stop!
          end
        end
      end

      pool.start!
      test_worker_pool.shutdown

      eval_rows
    end

    class << self
      def load(filenames, split: nil, languages: nil, version: nil)
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
          JSONUtils.load_file(filename).each do |hash|
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
