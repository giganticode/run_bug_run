require 'active_record'
require 'run_bug_run/evaluation'
require 'run_bug_run/bug'

class RunBugRun::Run < ActiveRecord::Base
  belongs_to :evaluation, inverse_of: :runs
  belongs_to :test
  belongs_to :bug

  enum :status, RunBugRun::Bug::STATUSES, suffix: true
  enum :bug_version, RunBugRun::Bug::VERSIONS
  enum :bug_variant, RunBugRun::Bug::VARIANTS

  def pass?
    status == 'pass' # must be string here
  end
end
