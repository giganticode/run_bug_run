require 'erb'
require 'set'
require 'fileutils'

module RunBugRun
  module CLI
    class CandidateVisualizer
      attr_reader :options

      COLORS = {
        'error' => 'black',
        'fail' => 'red',
        'pass' => 'green',
        'timeout' => 'yellow',
        'compilation_error' => 'gray'
      }.freeze

      def initialize(output, options)
        @options = options

        version = output.fetch('version')
        languages = output.fetch('languages').map(&:to_sym)
        split = output.fetch('split').to_sym

        dataset = RunBugRun::Dataset.new(version:)
        @bugs = dataset.load_bugs(split:, languages:)
        @tests = dataset.load_tests

        @results = EvaluationResults.new(
          output.fetch('results'),
          @bugs, @tests,
          only_plausible: @options.fetch(:only_plausible, false),
          candidate_limit: @options.fetch(:candidate_limit, nil)
        ).trim_to_bugs

        @height = @results.size
        @width = @results.candidates_per_bug
        @backgrounds = COLORS.transform_values { "background-color: #{_1};" }
        (2...COLORS.size).each do |n|
          COLORS.keys.combination(n).each do |c|
            @backgrounds[c.join('__')] = striped_background(COLORS.values_at(*c))
          end
        end
      end

      def striped_background(colors)
        f = 100.0 / (2 * colors.size)
        gradients = ["#{colors.first} #{f}%"]
        colors[1..].each_with_index do |color, index|
          gradients << "#{color} #{(index + 1) * f}%"
          gradients << "#{color} #{(index + 2) * f}%"
        end
        colors.each_with_index do |color, index|
          gradients << "#{color} #{(index * f) + 50}%"
          gradients << "#{color} #{((index + 1) * f) + 50}%"
        end
        "background-image: linear-gradient(90deg, #{gradients.join(', ')});"
      end

      def labels_tree(labels)
        tree = Hash.new { |h,k| h[k] = Hash.new(&h.default_proc) }
        labels.each do |label|
          parts = label.split('.')
          h = parts.take(parts.size - 1).inject(tree) do |acc, part|
            acc[part]
          end
          h[parts.last] = label
        end
        tree
      end

      def html_label_tree(tree, buffer = StringIO.new, prefix = [])
        tree.each do |name, t|
          new_prefix = prefix.dup << name
          full_label = new_prefix.join('.')
          bottom = !t.is_a?(Hash)
          class_name = bottom ? 'label-input' : 'label-level-input'
          buffer << "<div>"
          buffer << %(<input class="#{class_name}" type="checkbox" id="#{full_label}" />\n)
          buffer << %(<label for="#{full_label}">#{name}</label>\n)
          buffer << "</div>"
          if !bottom
            buffer << %(<div class="label-level">\n)
            html_label_tree(t, buffer, new_prefix)
            buffer << "</div>\n"
          end
        end
        puts buffer.string
        buffer.string
      end

      def render!
        template = File.read(File.join(RunBugRun.gem_data_dir, 'templates', 'vis', 'candidates.html.erb'))

        labels = Hash.new { |h, k| h[k] = Hash.new { |h, k| h[k] = Set.new } }
        labels_per_problem = Hash.new { |h, k| h[k] = Hash.new { |h, k| h[k] = Set.new } }

        data = Hash.new { |h, k| h[k] = Hash.new { |h, k| h[k] = {} } }
        @results.to_hash.each do |bug_id, candidates_results|
          bug = @bugs[bug_id]
          labels[bug.language][bug_id].merge(bug.labels) if bug.labels
          labels_per_problem[bug.language][bug.problem_id].merge(bug.labels) if bug.labels

          data[bug.language][bug.problem_id][bug_id] = candidates_results.map do |candidate_results|
            results = candidate_results.map { _1.fetch('result') }
            results.uniq!
            results.sort!
            results.join('__')
          end
        end


        language_names = RunBugRun::Bugs::LANGUAGE_NAME_MAP
        output_dir = '/tmp'
        data.each do |language, language_data|
          language_labels = labels[language]
          all_labels = Set.new
          language_labels.each_value { all_labels.merge _1 }
          html_tree = html_label_tree(labels_tree(all_labels))
          language_labels_per_problem = labels_per_problem[language]
          html = ERB.new(template).result(binding)

          filename = File.join(output_dir, "#{language}.html")
          puts "Writing #{filename}"
          File.write(filename, html)
        end

        css_filename = File.join(RunBugRun.gem_data_dir, 'templates', 'vis', 'pico.classless.css')
        FileUtils.cp css_filename, output_dir
      end
    end
  end
end
