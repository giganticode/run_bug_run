require 'erb'
require 'run_bug_run'

module RunBugRun
  class JUnitGenerator
    def initialize(bugs, tests, output_dir:, fixed: false)
      @bugs = bugs
      @output_dir = output_dir
      @tests = tests
      @fixed = fixed
    end

    def generate!
      @time = Time.now

      problem_ids = []

      @bugs.each do |bug|
        tests = @tests[bug.problem_id]
        generate_bug bug, tests
        problem_ids << bug.problem_id
      end

      problem_ids.each do |problem_id|
        tests = @tests[problem_id]
        tests.each do |test|
          generate_test test
        end
      end
    end

    private

    def generate_bug(bug, tests)
      package_name = "run_bug_run_#{bug.id}"
      template = File.read(File.join(RunBugRun.gem_data_dir, 'templates', 'java', 'BugTest.java.erb'))
      submission = bug.submission @fixed ? :fixed : :buggy
      test_class_name = "#{submission.main_class}Test"
      erb = ERB.new(template)

      src_dir = File.join(@output_dir, "bug_#{bug.id}", 'src', package_name)
      test_dir = File.join(@output_dir, "bug_#{bug.id}", 'test', package_name)

      FileUtils.mkdir_p src_dir
      FileUtils.mkdir_p test_dir

      content = erb.result(binding)
      File.write(File.join(test_dir, "#{test_class_name}.java"), content)


      submission_code = submission.code.sub(/package\s+([a-zA-Z0-9_.]+)\s*;/, '')
      bug_code = "package #{package_name};\n#{submission_code}"
      File.write(File.join(src_dir, "#{submission.main_class}.java"), bug_code)

      puts [src_dir, test_dir]
    end

    def generate_test(test)
      tests_dir = File.join(@output_dir, 'tests')
      FileUtils.mkdir_p tests_dir
      File.write(File.join(tests_dir, "input#{test.id}.txt"), test.input)
      File.write(File.join(tests_dir, "output#{test.id}.txt"), test.output)
    end

  end
end