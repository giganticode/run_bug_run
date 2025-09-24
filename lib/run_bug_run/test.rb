require 'active_record'

module RunBugRun
  class Test < ActiveRecord::Base
    enum :origin, {
      unknown: 0,
      codenet: 1,
      manual: 2,
      alphacode: 3,
      atcoder: 4
    }

    scope :active, -> { where(active: true) }

    has_many :bugs, foreign_key: :problem_id, primary_key: :problem_id, inverse_of: :tests
    has_many :runs, class_name: '::RunBugRun::Run', inverse_of: :test
    belongs_to :problem, foreign_key: :problem_id, primary_key: :problem_id, inverse_of: :tests

    def to_test_runner_test
      RunBugRun::TestRunner::Test.new(id:, problem_id:, input:, output:)
    end
  end
end