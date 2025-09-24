# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

$LOAD_PATH.unshift("#{__dir__}/../lib")
require 'run_bug_run'

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/test_*.rb"]
end

require "rubocop/rake_task"

RuboCop::RakeTask.new

task default: %i[test rubocop]

require 'erb'
require 'active_record'


class SeedLoader
  def initialize(seed_file)
    @seed_file = seed_file
  end
  def load_seed
    raise "Seed file '#{@seed_file}' does not exist" unless File.file?(@seed_file)
    load @seed_file
  end
end

include ActiveRecord::Tasks

DatabaseTasks.env = ENV['ENV'] || 'development'
DatabaseTasks.root = RunBugRun.root
DatabaseTasks.database_configuration = YAML.safe_load(ERB.new(RunBugRun.root.join('config', 'database.yml').read).result)
DatabaseTasks.db_dir = 'db'
DatabaseTasks.migrations_paths = 'db/migrate'
DatabaseTasks.seed_loader = SeedLoader.new('db/seeds.rb')

task :environment do
  ActiveRecord::Base.configurations = DatabaseTasks.database_configuration
  ActiveRecord::Base.establish_connection DatabaseTasks.env.to_sym
end

namespace :db do
  desc "Creates a new migration file with the specified name"
  task :generate, :name, :options do |t, args|
    require 'rails/generators'
    name, options = args[:name] || ENV['name'], args[:options] || ENV['options']
    unless name
      puts "Error: must provide name of migration to generate."
      puts "For example: rake #{t.name} name=add_field_to_form"
      abort
    end

    if options
      generator_params = [name] + options.gsub('/', ' ').split(" ")
    else
      generator_params = [name]
    end
    Rails::Generators.invoke "active_record:migration", generator_params
  end
end

load 'active_record/railties/databases.rake'
