require 'active_record'

module RunBugRun
  class Problem < ActiveRecord::Base
    has_many :bugs, foreign_key: :problem_id, primary_key: :problem_id, inverse_of: :problem
    has_many :tests, foreign_key: :problem_id, primary_key: :problem_id, inverse_of: :problem
    has_many :runs, class_name: '::RunBugRun::Run', inverse_of: :test
  end
end