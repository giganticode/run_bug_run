require 'run_bug_run/json_utils'
require 'csv'

module RunBugRun
  module CLI
    class Utils < SubCommand
      desc 'split_languages', 'splits evaluation results into separate files (per language)'
      method_option :o, desc: 'Output directory', type: :string, required: true
      def split_languages(filename)
        output = JSONUtils.load_file filename, symbolize_names: false

        version = output.fetch('version')
        languages = output.fetch('languages').map(&:to_sym)
        split = output.fetch('split').to_sym

        dataset = RunBugRun::Dataset.new(version:)
        bugs = dataset.load_bugs(split:, languages:)

        results_by_language = Hash.new { |h, k| h[k] = {} }
        output.fetch('results').each do |bug_id, results|
          language = bugs[bug_id].language
          results_by_language[language][bug_id] = results
        end

        output_dir = options[:o]

        FileUtils.mkdir_p(output_dir)

        languages.each do |language|
          language_filename = File.join(output_dir, File.basename(filename).sub('.json', "_#{language}.json"))
          JSONUtils.write_json(language_filename, {
                                 version:,
                                 languages: [language],
                                 split:,
                                 results: results_by_language.fetch(language)
                               })
        end
      end

      desc 'to_table', 'builds a table by grouping keys from multiple JSON output files'
      method_option :o, desc: 'Output filename', type: :string, required: true
      def to_table(*filenames)
        input_data = filenames.map { JSONUtils.load_file _1 }

        keys = input_data.flat_map(&:keys).uniq

        table = {}

        keys.each do |key|
          table[key] = input_data.map { _1.fetch(key, nil) }
        end

        CSV.open(options.fetch(:o), 'w') do |csv|
          csv << ['key', *filenames]
          table.each do |key, values|
            csv << [key, *values]
          end
        end
      end
    end
  end
end
