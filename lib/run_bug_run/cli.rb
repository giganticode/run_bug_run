require 'thor'
require 'csv'
require 'pp'
require 'run_bug_run/bug'
require 'run_bug_run/test'
require 'run_bug_run/fix_candidates'
require 'run_bug_run/cli/analyzer'
require 'run_bug_run/evaluator'

RunBugRun.initialize_database

module RunBugRun
  module CLI
    class SubCommand < Thor
      def self.banner(command, _namespace = nil, _subcommand = false)
        "#{basename} #{subcommand_prefix} #{command.usage}"
      end

      def self.subcommand_prefix
        name.gsub(/.*::/, '').gsub(/^[A-Z]/) do |match|
          match[0].downcase
        end.gsub(/[A-Z]/) { |match| "-#{match[0].downcase}" }
      end
    end

    class Main < Thor
      def self.exit_on_failure?
        true
      end

      no_commands do
        def seconds_to_time_str(seconds)
          format('%02d:%02d:%02d', seconds / 3600, (seconds / 60) % 60, seconds % 60)
        end

        def print_eval_summary(all_rows, bugs, tests, output_filename, start_time, end_time)
          elapsed_time = (end_time - start_time).to_f
          passing_rows = all_rows.select do |bug_id, candidate_runs|
            bug = bugs[bug_id]
            test_count = tests[bug.problem_id].size
            candidate_runs.any? { |runs| runs.count { _1.fetch(:result) == 'pass' } == test_count }
          end

          bugs_with_results = all_rows.count do |_bug_id, candidate_runs|
            candidate_runs.any?
          end

          bugs_without_results = all_rows.size - bugs_with_results

          bug_count = all_rows.size
          submission_count = all_rows.values.flatten(1).size
          run_count = all_rows.values.flatten(2).size
          bugs_per_s = (bug_count / elapsed_time).round(2)
          submissions_per_s = (submission_count / elapsed_time).round(2)
          runs_per_s = (run_count / elapsed_time).round(2)

          # Write to stderr, as we normally output JSON to stdout
          # for consistency ?
          RunBugRun.logger.then do |l|
            l.info "#{passing_rows.size}/#{all_rows.size} passed (#{(passing_rows.size / bugs_with_results.to_f * 100.0).round(2)}%, #{bugs_without_results} without results)"
            l.info "Evaluating #{bug_count} bugs (#{bugs_per_s}/s), #{submission_count} submissions (#{submissions_per_s}/s), #{run_count} runs (#{runs_per_s}/s) took #{seconds_to_time_str elapsed_time}"
            l.info "Evaluation results written to #{output_filename}"
            l.info "Use `rbugr analyze #{output_filename}` to analyze performance"
          end
        end
      end

      SPLITS = (RunBugRun::Bug.split_keys.map(&:to_s) << 'all').freeze
      ALL_LANGUAGES = Bug.language_keys.map(&:to_s)

      desc 'eval NAME [FILENAME]', 'create evaluation'
      method_option :version, desc: 'dataset version (defaults to most recent installed version)', type: :string
      method_option :languages, desc: 'languages to evaluate (defaults to all)', type: :array,
                                default: ALL_LANGUAGES
      method_option :split, desc: 'split to evaluate (defaults to the test set)', type: :string,
                            enum: SPLITS
      method_option :bug_version, desc: 'which version (buggy or fixed) to evaluate',
                            type: :string, enum: %w[buggy fixed candidate], default: 'candidate'
      method_option :abort_on_error, desc: 'stop execution on first error', type: :boolean, default: true
      method_option :abort_on_fail, desc: 'stop execution on first failing test', type: :boolean, default: false
      method_option :abort_on_timeout, desc: 'stop execution after specified number of seconds', type: :numeric,
                                       default: 1
      method_option :stop_after_first_pass, desc: 'stop evaluating a specific bug after first passing candidate', type: :boolean, default: true
      method_option :workers, desc: 'number of workers to use for evaluation', type: :numeric, default: 8
      method_option :limit, desc: 'only evaluate a limited number of bugs', type: :numeric, default: nil
      method_option :bug_variant, desc: 'variant to evaluate', type: :string, default: nil
      method_option :min_change_count, desc: 'mininum change count', type: :numeric, default: nil
      method_option :max_change_count, desc: 'maximum change count', type: :numeric, default: nil
      method_option :skip_bad_bugs, desc: 'skip a bug if an existing run (possibly of a different test case) timed out', type: :boolean, default: true
      method_option :log_level, desc: 'log level', type: :string, default: 'info', enum: %w[debug info warn error fatal unknown]
      def eval(name, fix_candidates_filename = nil)
        logger = Logger.new
        logger.level = options.fetch(:log_level)

        # version = options.fetch(:version) { RunBugRun::Dataset.last_version }
        languages = options.fetch(:languages, Bug.language_keys)
        unless (languages - Bug.language_keys).empty?
          raise ArgumentError, "invalid languages: must be subset of #{Bug.language_keys}"
        end

        # dataset = RunBugRun::Dataset.new(version:)
        split = options.fetch(:split, :test).to_sym
        bug_version = options.fetch(:bug_version).to_sym
        # bugs = dataset.load_bugs(split:, languages:)

        bugs = Bug.active
        bugs = bugs.where(language: languages) unless languages == ALL_LANGUAGES
        bugs = bugs.where(split:) unless split == :all

        if (min_change_count = options[:min_change_count])
          bugs = bugs.where('change_count >= ?', min_change_count)
        end

        if (max_change_count = options[:max_change_count])
          bugs = bugs.where('change_count <= ?', max_change_count)
        end

        evaluation = Evaluation.create_with(started_at: Time.now).find_or_create_by(name:)
        fix_candidates = FixCandidates.load(fix_candidates_filename) if fix_candidates_filename
        # tests = dataset.load_tests
        tests = nil

        limit = options[:limit]
        bugs = bugs.limit(limit) if limit

        # We don't need accurate time. Time.now gives more human-friendly output
        start_time = Time.now # Process.clock_gettime(Process::CLOCK_MONOTONIC)

        Thread.abort_on_exception = true
        evaluator = Evaluator.new(
          evaluation, bugs,
          bug_version: bug_version,
          bug_variant: options[:bug_variant]&.to_sym,
          skip_bad_bugs: options.fetch(:skip_bad_bugs),
          logger:
        )

        RunBugRun.logger.info "Evaluating #{evaluator.total_bug_count} bugs for #{evaluation.name}/#{evaluation.id} (#{evaluator.evaluated_bug_count} already evaluated)"

        results = evaluator.evaluate!(
                                 candidates: fix_candidates,
                                 abort_on_timeout: options.fetch(:abort_on_timeout),
                                 abort_on_fail: options.fetch(:abort_on_fail),
                                 abort_on_error: options.fetch(:abort_on_error),
                                 stop_after_first_pass: options.fetch(:stop_after_first_pass),
                                 workers: options.fetch(:workers))

        end_time = Time.now # Process.clock_gettime(Process::CLOCK_MONOTONIC)

        evaluation.update!(ended_at: end_time)

        json = {
          split:,
          languages:,
          options:,
          bug_version:,
          start_time:,
          end_time:,
          results:
        }

        print_eval_summary results, bugs, tests, output_filename, start_time, end_time
        JSONUtils.write_json output_filename, json, compression: :gzip
      end


      desc 'export OUTPUT_DIR', 'export to JSONL'
      EXPORTED_COLS = %i[id buggy_code fixed_code split language runtime_errors].freeze
      EXPORT_SPLITS = %i[train valid test].freeze
      def export(output_dir)
        binding.irb
        EXPORT_SPLITS.each do |split|
          rows = []
          RunBugRun::Bug.active.where(split: ).find_in_batches(batch_size: 5_000) do |batch|
            batch.pluck(*EXPORTED_COLS).each do |row|
              hash_row = {}
              EXPORTED_COLS.each_with_index do |col, index| 
                hash_row[col] = row[index]
              end
              rows << hash_row
            end
          end
          RunBugRun::JSONUtils.write_jsonl(File.join(output_dir, "#{split}.jsonl.gz"), rows)
          rows.clear
        end
      end

      desc 'junit BUG_IDS', 'generate JUnit tests for the specified bugs'
      method_option :o, desc: 'Output directory', type: :string, required: true
      method_option :version, desc: 'Bug version (prediction, buggy or fixed)', type: :string, required: true
      method_option :limit, desc: 'Only export the first n bugs', type: :numeric, default: nil
      def junit(*bug_ids)
        require 'run_bug_run/junit_generator'

        bugs = Bugs.load_internal :test, languages: :java

        bugs = bugs.values_at(*bug_ids.map(&:to_i)) if bug_ids.any?

        version = options.fetch(:version).to_sym
        output_dir = options.fetch(:o)

        tests = Tests.load_internal

        bugs = bugs.take(options[:limit]) if options[:limit]
        generator = JUnitGenerator.new(bugs, tests, output_dir:, version:)
        generator.generate!
      end

      desc 'analyze_cardumen OUTPUT_FILE', 'analyze output file'
      method_option :by_language, desc: 'Analyze per language', type: :boolean, default: false
      method_option :by_change_count, desc: 'Analyze per language', type: :boolean, default: false
      method_option :by_label, desc: 'Analyze per label', type: :boolean, default: false
      method_option :strong_points, desc: 'Analyze strong points', type: :boolean, default: nil
      method_option :weak_points, desc: 'Analyze strong points', type: :boolean, default: nil
      method_option :by_exception, desc: 'Analyze per exception', type: :boolean, default: false
      method_option :format, desc: 'Output format for plausibility', type: :string, enum: %w[rel abs verbose], default: 'rel'
      method_option :o, desc: 'Output filename', type: :string, required: false, default: nil
      def analyze_cardumen(output_filename)
        output = {
          'split' => 'test',
          'languages' => ['java'],
          'results' => JSONUtils.read(output_filename, symbolize_names: false),
          'version' => RunBugRun::Dataset.last_version
        }
        analyzer = Analyzer.new(output, options.merge(only_plausible: true))
        report = analyzer.analyze

        json_output = JSON.pretty_generate(report.sort.to_h)
        if (o = options[:o])
          File.write(o, json_output)
        else
          puts json_output
        end

      end

      desc 'failing OUTPUT_FILE', 'show ids of failing bugs'
      def failing(output_filename)
        eval_output = JSONUtils.read output_filename
        results = eval_output[:results]

        failing = results.select do |_bug_id, candidate_runs|
          candidate_runs.any? { |runs| runs.any? { _1.fetch(:result) != 'pass' } }
        end

        puts JSON.pretty_generate(failing)
      end

      desc 'passing OUTPUT_FILE', 'show ids of passing bugs'
      def passing(output_filename)
        eval_output = JSONUtils.read output_filename
        results = eval_output[:results]

        passing = results.select do |_bug_id, candidate_runs|
          candidate_runs.any? { |runs| runs.all? { _1.fetch(:result) == 'pass' } }
        end

        puts JSON.pretty_generate(passing)
      end

      no_commands do
        def abs_rel(options, a, b)
          if options.fetch(:abs)
            "#{a}/#{b}"
          else
            (a.to_f / b.to_f).round(4)
          end
        end
      end


      desc 'analyze EVALUATION_NAME [CANDIDATES_FILENAME]', 'analyze evaluation results'
      # method_option :only_plausible, desc: 'The file to analyze contains plausible bug candidates only', type: :boolean,
      #                              default: false
      # method_option :ignore_missing, desc: 'Ignore bugs with no results in the evaluation result file', type: :boolean, default: false
      # method_option :candidate_limit, desc: 'Limit evaluation to specified number of candidates', type: :numeric, default: nil
      def analyze(evaluation_name, fix_candidates_filename = nil)

        evaluation = RunBugRun::Evaluation.find_by_name!(evaluation_name)

        fix_candidates = FixCandidates.load(fix_candidates_filename) if fix_candidates_filename

        counts_select = Arel.sql <<~SQL
          bug_id, candidate_index,
          COUNT(*) FILTER(WHERE status = 0) AS pass_count,
          COUNT(*) FILTER(WHERE status <> 0) = 0 AS all_passed,
          COUNT(*) FILTER(WHERE status = 0) > 0 AS any_passed,
          COUNT(*) FILTER(WHERE status = 1) AS fail_count,
          COUNT(*) FILTER(WHERE status = 2) AS error_count,
          COUNT(*) FILTER(WHERE status = 3) AS timeout_count,
          COUNT(*) FILTER(WHERE status = 4) AS compilation_error_count,
          COUNT(*) AS total_count
        SQL

        test_counts = RunBugRun::Test.active.group(:problem_id).select(:problem_id, "COUNT(*) AS test_count")
        counts = RunBugRun::Run.where(evaluation:).group(:bug_id, :candidate_index).select(counts_select)
        max_counts = RunBugRun::Run.from('counts').group(:bug_id).select(Arel.sql('counts.bug_id, MAX(pass_count) AS max_pass_count'))
        max_bugs = RunBugRun::Bug.joins("INNER JOIN counts ON counts.bug_id = bugs.id")
                                 .joins("INNER JOIN max_counts ON max_counts.bug_id = bugs.id AND counts.pass_count = max_counts.max_pass_count")
                                 .joins("INNER JOIN test_counts ON test_counts.problem_id = bugs.problem_id")
                                 .select("*, ROW_NUMBER() OVER(PARTITION BY id ORDER BY id) AS row_number")
        single_bugs = RunBugRun::Bug.from('max_bugs').where('row_number = 1').select('*')
        bugs = RunBugRun::Bug.with(counts:, max_counts:, test_counts:, max_bugs:, single_bugs:).from('single_bugs AS bugs').select('bugs.*, counts.*, test_counts.*')

        p bugs.pluck("AVG(all_passed)")
        p bugs.where('pass_count = test_count AND NOT all_passed').count
        p bugs.where('all_passed AND NOT pass_count = test_count').count
        puts bugs.group(:language).order('AVG(all_passed) DESC').pluck(Arel.sql('language, AVG(all_passed), COUNT(*)')).map(&:to_csv).join
        puts bugs.group(:problem_id).order('AVG(all_passed) DESC').having(Arel.sql('COUNT(*) > 50')).pluck(Arel.sql('problem_id, AVG(all_passed), COUNT(*)')).map(&:to_csv).join
        puts bugs.group(:change_count).order('AVG(all_passed) DESC').having(Arel.sql('COUNT(*) > 50')).pluck(Arel.sql('change_count, AVG(all_passed), COUNT(*)')).map(&:to_csv).join

        # pass_count = RunBugRun::Bug.from('single_bugs').pluck("AVG(pass_count)")
        
        # bugs.pluck('AVG(pass_count)')
        binding.irb
      end

      no_commands do
        def to_csv(obj)
          case obj
          when Hash
            obj.map{ |entry| CSV.generate_line(entry) }.join
          else
            raise "cannto convert #{obj.class} to CSV"
          end
        end
      end

      desc 'analyze EVALUATION_NAME [CANDIDATES_FILENAME]', 'analyze evaluation results'
      method_option :max_candidate_index, desc: 'Only consider candidates subset of candidates', type: :numeric, default: nil
      def analyze2(evaluation_name, fix_candidates_filename = nil)

        evaluation = RunBugRun::Evaluation.find_by_name!(evaluation_name)

        fix_candidates = FixCandidates.load(fix_candidates_filename) if fix_candidates_filename

        counts_select = Arel.sql <<~SQL
          bug_id, candidate_index,
          COUNT(*) FILTER(WHERE status = 0) AS pass_count,
          COUNT(*) FILTER(WHERE status <> 0) = 0 AS all_passed,
          COUNT(*) FILTER(WHERE status = 0) > 0 AS any_passed,
          COUNT(*) FILTER(WHERE status = 1) AS fail_count,
          COUNT(*) FILTER(WHERE status = 2) AS error_count,
          COUNT(*) FILTER(WHERE status = 3) AS timeout_count,
          COUNT(*) FILTER(WHERE status = 4) AS compilation_error_count,
          COUNT(*) AS total_count,

          /*
             This assigns 1 to the candidate with the highest pass count (best candidate) for a particular bug (i.e., for the partition).
             We later restrict our analysis only to the best candidate as if the best candidate is not passing all tests, none of the candidates is.
          */
          ROW_NUMBER() OVER(PARTITION BY bug_id ORDER BY COUNT(*) FILTER(WHERE status = 0) DESC) AS count_row_number
        SQL

        test_counts = RunBugRun::Test.active.group(:problem_id).select(:problem_id, "COUNT(*) AS test_count")
        counts = RunBugRun::Run.where(evaluation:).group(:bug_id, :candidate_index).select(counts_select)

        binding.irb

        if max_candidate_index = options[:max_candidate_index]
          counts = counts.where('candidate_index <= ?', max_candidate_index)
        end

        joined_bugs = RunBugRun::Bug.active.joins("INNER JOIN counts ON counts.bug_id = bugs.id AND counts.count_row_number = 1")
                                 .joins("INNER JOIN test_counts ON test_counts.problem_id = bugs.problem_id").select('*')
        bugs = RunBugRun::Bug.with(counts:, test_counts:, joined_bugs:).from('joined_bugs AS bugs')

        p ['xx',bugs.pluck("AVG(all_passed)"), bugs.where('pass_count = test_count AND NOT all_passed').count, bugs.where('all_passed AND NOT pass_count = test_count').count]
        puts bugs.group(:language).order('language ASC').pluck(Arel.sql('AVG(all_passed), COUNT(*)')).map{[_1].to_csv}.join
        #puts bugs.group(:language).order('AVG(all_passed) DESC').pluck(Arel.sql('language, AVG(all_passed), COUNT(*)')).map(&:to_csv).join
        puts bugs.group(:problem_id).order('AVG(all_passed) DESC').having(Arel.sql('COUNT(*) > 50')).pluck(Arel.sql('problem_id, AVG(all_passed), COUNT(*)')).map(&:to_csv).join
        puts bugs.group(:change_count).order('AVG(all_passed) DESC').having(Arel.sql('COUNT(*) > 50')).pluck(Arel.sql('change_count, AVG(all_passed), COUNT(*)')).map(&:to_csv).join
      end


      require 'run_bug_run/cli/bugs'
      desc 'bugs', 'get information on bugs'
      subcommand 'bugs', CLI::Bugs

    end
  end
end
