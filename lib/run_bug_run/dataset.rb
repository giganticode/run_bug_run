require 'open-uri'
require 'progressbar'
require 'digest'

require 'run_bug_run/bugs'

module RunBugRun
  class Dataset
    #DEFAULT_BASE_URL = 'https://github.com/gigianticode/run_bug_run/%{version}/%{filename}'.freeze
    DEFAULT_BASE_URL = 'https://github.com/giganticode/run_bug_run_data/releases/download/v%{version}/%{filename}'.freeze
    MANIFEST_FILENAME = 'Manifest.json.gz'.freeze
    INDEX_FILENAME = 'Index.json.gz'.freeze

    attr_reader :version

    def initialize(version: self.class.last_version)
      @version = version
    end

    def load_bugs(split: nil, languages: RunBugRun::Bugs::ALL_LANGUAGES)
      raise ArgumentError, "invalid split '#{split}'" unless split.nil? || RunBugRun::Bugs::SPLITS.include?(split)
      files = self.files.select do |file|
        file[:type] == 'bugs' &&
        (split.nil? || file[:split].to_sym == split) &&
        languages.include?(file[:language].to_sym)
      end
      filenames = files.map { File.join(data_dir, _1.fetch(:filename)) }
      RunBugRun::Bugs.load(filenames)
    end

    def load_tests
      filename = File.join(data_dir, 'tests_all.jsonl.gz')
      RunBugRun::Tests.load(filename)
    end

    def stats
      files.filter { _1[:type] == 'bugs' }.group_by { _1[:split] }.map do |split, files|
        by_language = files.group_by { _1[:language] }.transform_values { _1.sum { |f| f[:size] } }
        [
          split, {
            by_language: by_language,
            total: by_language.values.sum
          }
        ]
      end.to_h
    end

    def find_filename_by_id(type, id)
      files = self.files.select do
        _1[:type].to_sym == type
      end
      file = find_file_by_id(files, id)
      return nil if file.nil?

      File.join(data_dir, file.fetch(:filename))
    end

    def data_dir
      File.join(self.class.versions_dir, @version)
    end

    def manifest
      manifest_filename = File.join(data_dir, MANIFEST_FILENAME)
      @manifest ||= JSONUtils.load_file(manifest_filename)
    end

    def index
      @index ||= JSONUtils.load_file(File.join(data_dir, INDEX_FILENAME), symbolize_names: false)
    end

    class << self
      def last_version
        versions.max_by {  Gem::Version.new(_1) }
      end

      def versions
        Dir[File.join(versions_dir, '*')].map { File.basename(_1) }
      end

      def versions_dir
        File.join(RunBugRun.data_dir, 'versions')
      end

      def download(version:, force: false, base_url: DEFAULT_BASE_URL)
        manifest_io = download_file(MANIFEST_FILENAME, version, force:, base_url:)
        manifest_io.rewind
        manifest = JSONUtils.load_json(manifest_io, compression: :gzip)

        files = manifest.fetch(:files)
        total_bytes = files.sum { _1.fetch(:bytes) }

        progress_bar = ProgressBar.create(total: total_bytes)

        downloaded_bytes = 0
        progress_proc = lambda do |progress|
          progress_bar.progress = [downloaded_bytes + progress, total_bytes].min
        end

        files.each do |file|
          progress_bar.title =
            case file[:type]
            when 'bugs'
              "Downloading #{Bugs::LANGUAGE_NAME_MAP[file[:language].to_sym]} bugs"
            when 'tests'
              'Downloading tests'
            when 'index'
              'Downloading index'
            else
              '???'
            end

          download_file(file.fetch(:filename), version, force:, base_url:, progress_proc:, md5: file.fetch(:md5))
          downloaded_bytes += file.fetch(:bytes)
        end
      ensure
        manifest_io&.close
      end

      def download_file(filename, version, force:, base_url:, progress_proc: nil, md5: nil)
        url = format(base_url, version:, filename:)
        uri = URI.parse(url)
        target_path = File.join(versions_dir, version, filename)
        if !force && File.exist?(target_path)
          return File.open(target_path, 'r')
        end

        RunBugRun.logger.debug("Downloading '#{url}' to #{target_path}")

        download = uri.open(
          # content_length_proc: lambda { |content_length|
          #   if total_bytes.nil? && content_length&.positive?
          #     progress_bar.total = content_length
          #   end
          # },
          progress_proc:
        )

        FileUtils.mkdir_p(File.dirname(target_path))
        IO.copy_stream(download, target_path)

        if md5
          download.rewind
          if md5 != Digest::MD5.hexdigest(download.read)
            RunBugRun.logger.warn "md5 check failed, please redownload. Use --force to overwrite previous files"
          end
        end

        download
      end
    end

    private

    def files
      manifest.fetch(:files)
    end

    def find_file_by_id(files, id)
      id = Integer(id)

      files.find do |file|
        filename = file.fetch(:filename)
        index['ids'][filename].include? id
      end
    end

  end
end