require 'active_record'

module RunBugRun
  class Evaluation < ActiveRecord::Base
    has_many :runs, inverse_of: :evaluation, dependent: :delete_all
  end
end