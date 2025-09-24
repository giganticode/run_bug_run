module RunBugRun
  module CLI
    class Bugs < SubCommand
      no_commands {
        def find_filename_by_id(id)
          version = options.fetch(:version) { RunBugRun::Dataset.last_version }
          dataset = RunBugRun::Dataset.new(version:)
          filename = dataset.find_filename_by_id(:bugs, id)
          if filename.nil?
            puts "Bug with id #{id} not found"
            exit(1)
          end
 
          [dataset, filename]
        end

        def load_bug(id)
          dataset, filename = find_filename_by_id(id)
          bugs = RunBugRun::Bugs.load([filename])
          [dataset, bugs[id]]
        end
      }

      desc 'locate ID', 'show file that contains given bug'
      def locate(id)
        _, filename = find_filename_by_id(id)
        puts JSON.pretty_generate(filename)
      end

      desc 'diff ID', 'show diff of given bug'
      method_option :using, type: :string, enum: %w[diffy git], default: 'diffy'
      def diff(id)
        bug = RunBugRun::Bug.find(id)
        puts bug.diff(using: options[:using].to_sym)
      end

      desc 'show ID', 'show bug for given ID'
      method_option :version, type: :string
      method_option :tests, desc: 'show tests for this bug', type: :boolean, default: false
      # method_option :language, type: :string, enum: RunBugRun::Bugs::ALL_LANGUAGES.map(&:to_s)
      # method_option :split, type: :string, enum: RunBugRun::Bugs::SPLITS.map(&:to_s)
      def show(id)
        bug = RunBugRun::Bug.find(id)
        hash = {
          id: bug.id,
          language: bug.language,
          problem_id: bug.problem_id,
          change_count: bug.change_count,
          labels: bug.labels,
          errors: bug.runtime_errors,
          buggy_code: bug.buggy_code,
          fixed_code: bug.fixed_code
        }

        if options[:tests]
          bug_tests = RunBugRun::Test.active.where(problem_id: bug.problem_id)
          hash[:tests] = bug_tests.map(&:serializable_hash)
        end

        # puts JSON.pretty_generate(hash)
        puts bug.fixed_code
      end

      desc 'exec ID [FILES]', 'execute specified bug'
      method_option :bug_version, desc: 'which version (buggy or fixed) to evaluate',
                            type: :string, enum: %w[buggy fixed], default: 'buggy'
      method_option :abort_on_error, desc: 'stop execution on first error', type: :boolean, default: false
      method_option :abort_on_fail, desc: 'stop execution on first failing test', type: :boolean, default: false
      method_option :abort_on_timeout, desc: 'stop execution after specified number of seconds', type: :numeric, default: 1
      method_option :input, desc: 'custom input (if omitted test input is used)', type: :string, alias: :i, repeatable: true
      method_option :fix_candidates, desc: 'file with fix candidate predictions', type: :string
      method_option :candidate_index, desc: 'candidate index to execute (only if executing fix candidate)', type: :numeric, default: 0
      def exec(id)
        bug = RunBugRun::Bug.find(id)
        tests = RunBugRun::Test.active.where(problem_id: bug.problem_id).map(&:to_test_runner_test)
        logger = ::Logger.new($stdout)
        test_worker_pool = TestWorkerPool.new size: 1, logger: logger

        if (fix_candidates_filename = options[:fix_candidates])
          fix_candidates = FixCandidates.load(fix_candidates_filename)
          program = fix_candidates[id][options.fetch(:candidate_index)]
        else
          program = bug.to_program(options.fetch(:bug_version))
        end

        abort_on_timeout = options.fetch(:abort_on_timeout)
        abort_on_error = options.fetch(:abort_on_error)
        abort_on_fail = options.fetch(:abort_on_fail)

        runs, _worker_info = test_worker_pool.submit(program, tests,
                                       abort_on_timeout:,
                                       abort_on_error:,
                                       abort_on_fail:)

        puts JSON.pretty_generate(runs.map(&:to_h))
        puts tests.inspect
        puts runs.map{ _1.status}.tally
      end

    end
  end
end