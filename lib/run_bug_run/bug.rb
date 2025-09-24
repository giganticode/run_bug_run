require 'run_bug_run/program'
require 'run_bug_run/diffing'
require 'run_bug_run/parsing'
require 'run_bug_run/json_utils'
require 'active_record'

module RunBugRun
  class Bug < ActiveRecord::Base
    include Parsing
    include Diffing

    LANGUAGE_NAMES = {
      c: 'C',
      cpp: 'C++',
      javascript: 'JavaScript',
      java: 'Java',
      ruby: 'Ruby',
      python: 'Python',
      php: 'PHP',
      go: 'Go',
      c_sharp: 'C#'
    }.with_indifferent_access.freeze

    VERSIONS = {
      buggy: 0,
      fixed: 1,
      candidate: 2
    }.with_indifferent_access.freeze

    VARIANTS = {
      default: 0
    }.with_indifferent_access.freeze

    STATUSES = {
      pass: 0,
      fail: 1,
      error: 2,
      timeout: 3,
      compilation_error: 4
    }.with_indifferent_access.freeze

    FILENAME_EXTS = {
      c: 'c',
      cpp: 'cpp',
      javascript: 'js',
      java: 'java',
      ruby: 'rb',
      python: 'py',
      php: 'php',
      go: 'go',
      c_sharp: 'cs'
    }.with_indifferent_access.freeze

    def filename_ext = FILENAME_EXTS.fetch language

    class << self
      def language_keys = @languages_a ||= languages.keys
      def split_keys = @splits_a ||= splits.keys

      def label_id_to_name(label_id)
        load_label_names
        @label_names[label_id] 
      end

      def label_ids_to_names(label_ids)
        load_label_names
        label_ids.map { _1 == '+' || _1 == '-' ? _1 : @label_names[_1] }
      end

      private
      def load_label_names
        @label_names ||= begin
          RunBugRun::JSONUtils.read RunBugRun.gem_data_dir.join('labels', 'names.json.gz')
        end
      end
    end


    enum :language, {
      c: 0, cpp: 1, javascript: 2,
      java: 3, ruby: 4, python: 5,
      php: 6, go: 7, c_sharp: 8
    }

    enum :split, {train: 0, valid: 1, test: 2, unfiltered: 3}, suffix: true

    has_many :tests, foreign_key: :problem_id, primary_key: :problem_id
    has_many :active_tests, -> { active }, foreign_key: :problem_id, primary_key: :problem_id, class_name: 'Test'
    has_many :runs, class_name: 'Run', inverse_of: :bug, dependent: :delete_all

    belongs_to :problem, foreign_key: :problem_id, primary_key: :problem_id, inverse_of: :bugs

    scope :active, -> { where(active: true) }

    scope :test, -> { active.where(split: :test)}
    scope :train, -> { active.where(split: :train)}
    scope :valid, -> { active.where(split: :valid)}

    # scope :with_labels, (language, *labels) -> { where("label_ids") }

    def labels
      # self.class.labels_for_ids language, *label_ids
      label_ids.map { self.class.label_ids_to_names _1 }
    end

    def test_runner_tests
      active_tests.map(&:to_test_runner_test)
    end

    def diff(using: :diffy, buggy_code: self.buggy_code, fixed_code: self.fixed_code, **options)
      case using
      when :diffy
        diffy_diff(buggy_code, fixed_code, **options)
      when :git
        git_diff(buggy_code, fixed_code, **options)
      when :pq_profile
        pq_profile_diff(buggy_code, fixed_code, **options)
      when :tree_sitter
        tree_sitter_diff(buggy_code, fixed_code, **options)
      else
        raise ArgumentError, "invalid differ '#{using}'"
      end
    end

    def code(version)
      case version
      when :buggy, 'buggy', 0
        buggy_code
      when :fixed, 'fixed', 1
        fixed_code
      else
        raise ArgumentError, "version must be either :buggy or :fixed not #{version}"
      end
    end

    def to_program(version)
      case version
      when :buggy, 'buggy', 0
        code = buggy_code
        main_class = buggy_main_class
      when :fixed, 'fixed', 1
        code = fixed_code
        main_class = fixed_main_class
      else
        raise ArgumentError, "version must be either :buggy or :fixed not #{version}"
      end

      Program.new(
        code:,
        bug_id: id,
        bug_variant: nil,
        bug_version: version,
        main_class:,
        language:,
        problem_id:
      )
    end


  end
end