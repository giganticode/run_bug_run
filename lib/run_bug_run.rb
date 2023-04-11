# frozen_string_literal: true

require_relative "run_bug_run/version"
require 'logger'

module RunBugRun
  class Error < StandardError; end
  # Your code goes here...

  def self.root
    File.expand_path('..', __dir__)
  end

  def self.data_dir
    user_data_dir = ENV.fetch('XDG_DATA_HOME') { File.join(Dir.home, '.local', 'share') }
    File.join(user_data_dir, 'run_bug_run')
  end

  def self.gem_data_dir
    File.join(root, 'data')
  end

  def self.logger
    @logger ||= ::Logger.new($stderr)
  end
end

require "run_bug_run/bugs"
require "run_bug_run/dataset"