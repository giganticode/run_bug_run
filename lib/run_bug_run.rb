# frozen_string_literal: true

require_relative "run_bug_run/version"
require 'logger'
require 'yaml'
require 'active_record'

module RunBugRun

  class Error < StandardError; end
  # Your code goes here...

  def self.root
    @root ||= Pathname.new(File.expand_path('..', __dir__))
  end

  def self.data_dir
    user_data_dir = ENV.fetch('XDG_DATA_HOME') { File.join(Dir.home, '.local', 'share') }
    File.join(user_data_dir, 'run_bug_run')
  end

  def self.gem_data_dir
    root.join('data')
  end

  def self.logger
    @logger ||= ::Logger.new($stderr)
  end

  def self.initialize_database(env = 'development')
    db_config = YAML.load_file(root.join('config', 'database.yml').to_path)
    ActiveRecord::Base.establish_connection(db_config.fetch(env))
    ActiveRecord::Base.connection.execute 'PRAGMA journal_mode = WAL'
  end
end

# require "run_bug_run/bugs"
# require "run_bug_run/dataset"