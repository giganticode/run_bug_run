require 'run_bug_run/dataset'

module RunBugRun
  module CLI
    class Dataset < SubCommand
      desc 'version', 'show current version'
      def version
        puts JSON.pretty_generate(RunBugRun::Dataset.last_version)
      end

      desc 'versions', 'list all versions'
      def versions
        puts JSON.pretty_generate(RunBugRun::Dataset.versions)
      end

      desc 'download VERSION', 'download dataset at specific version'
      # method_option :version, desc: 'Dataset version', type: :string, required: true
      method_option :force, desc: 'Force redownload', type: :boolean, default: false
      def download(version)
        RunBugRun::Dataset.download(version: version, force: options[:force])
      end

      desc 'stats', 'show dataset statistics'
      def stats
        dataset = RunBugRun::Dataset.new
        puts JSON.pretty_generate(dataset.stats)
      end
    end
  end
end