require 'run_bug_run/dataset'

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
      def diff(id)
        _, bug = load_bug(id)
        puts bug.diff(:buggy, :fixed)
      end

      desc 'show ID', 'show bug for given ID'
      method_option :version, type: :string
      method_option :tests, desc: 'show tests for this bug', type: :boolean, default: false
      # method_option :language, type: :string, enum: RunBugRun::Bugs::ALL_LANGUAGES.map(&:to_s)
      # method_option :split, type: :string, enum: RunBugRun::Bugs::SPLITS.map(&:to_s)
      def show(id)
        dataset, bug = load_bug(id)
        hash = {
          id: bug.id,
          language: bug.language,
          problem_id: bug.problem_id,
          change_count: bug.change_count,
          labels: bug.labels,
          errors: bug.buggy_submission.errors
        }

        if options[:tests]
          tests = dataset.load_tests
          bug_tests = tests[bug.problem_id]
          hash[:tests] = bug_tests.map(&:to_h)
        end

        puts JSON.pretty_generate(hash)
      end

      desc 'exec ID [FILES]', 'execute specified bug'
      method_option :fixed, desc: 'run the fixed version of the specified bug (as a sanity check)', type: :boolean, default: false
      method_option :abort_on_error, desc: 'stop execution on first error', type: :boolean, default: true
      method_option :abort_on_fail, desc: 'stop execution on first failing test', type: :boolean, default: false
      method_option :abort_on_timeout, desc: 'stop execution after specified number of seconds', type: :numeric, default: 1
      method_option :input, desc: 'custom input (if omitted test input is used)', type: :string, alias: :i, repeatable: true
      def exec(id)
        dataset, bug = load_bug(id)
        tests = dataset.load_tests

        test_worker_pool = TestWorkerPool.new size: 1

        submission =
          if options.fetch(:fixed)
            bug.fixed_submission
          else
            bug.buggy_submission
          end

        abort_on_timeout = options.fetch(:abort_on_timeout)
        abort_on_error = options.fetch(:abort_on_error)
        abort_on_fail = options.fetch(:abort_on_fail)

        submission_tests =
          if (inputs = options[:input])
            inputs.map { |input| RunBugRun::Test.new id: nil, input:, output: '' }
          else
            tests[bug.problem_id]
          end

        runs, _worker_info = test_worker_pool.submit(submission, submission_tests,
                                       abort_on_timeout:,
                                       abort_on_error:,
                                       abort_on_fail:)

        puts JSON.pretty_generate(runs)
      end

    end
  end
end