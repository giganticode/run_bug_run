require 'run_bug_run/evaluation_results'

module RunBugRun
  module CLI
    class Analyzer
      attr_reader :options

      def initialize(output, options)
        @options = options
        load(output)
      end

      def analyze
        total_bugs = @options[:only_plausible] || @options[:ignore_missing] ? @bugs.size : @results.size

        plausible_count = @results.plausible_count

        report = {
          plausibility_rate: format_rate(plausible_count, total_bugs),
          plausible: plausible_count,
          total: total_bugs
        }

        analyze_by_label(report) if options.fetch(:by_label)
        analyze_weak_strong_points(report) if options[:strong_points] || options[:weak_points]
        analyze_by_language(report) if options.fetch(:by_language) && !options[:only_passing]
        analyze_by_exception(report) if options.fetch(:by_exception)
        analyze_by_change_count(report) if options.fetch(:by_change_count)

        report
      end

      def inspect
        "#<#{self.class.name}: size=#{@bugs.size}>"
      end

      private

      def load(output)
        version = output.fetch('version')
        languages = @options.fetch(:languages) { output.fetch('languages') }.map(&:to_sym)
        split = output.fetch('split').to_sym

        dataset = RunBugRun::Dataset.new(version:)
        @bugs = dataset.load_bugs(split:, languages:)
        @tests = dataset.load_tests unless @options[:only_plausible]

        @results = EvaluationResults.new(
          output.fetch('results'),
          @bugs, @tests,
          only_plausible: @options.fetch(:only_plausible, false),
          candidate_limit: @options.fetch(:candidate_limit, nil)
        )

        @results = @results.trim_to_bugs
        @bugs = @bugs.select_bugs_with_results(@results) if options.fetch(:ignore_missing, false)
      end

      def format_rate(plausible, total)
        format = @options.fetch(:format, :rel)
        case format
        when 'abs'
          "#{plausible}/#{total}"
        when 'rel'
          (plausible / total.to_f).round(4)
        when 'verbose'
          "#{plausible}/#{total} #{(plausible / total.to_f).round(4)}"
        when 'dict'
          {total:, plausible:, rate: plausible / total.to_f}
        else
          raise "invalid plausibility rate format #{format}"
        end
      end

      def analyze_by_language(report)
        @results.group_by_language.each do |language, results|
          plausible_count = results.plausible_count
          report[:"plausibility_rate_#{language}"] = format_rate(plausible_count, results.size)
        end
      end

      def analyze_by_change_count(report)
        @results.group_by_change_count.each do |change_count, results|
          plausible_count = results.plausible_count
          report[:"plausibility_rate_change_count#{change_count}"] =
            format_rate(plausible_count, results.size)
        end
        # runs.group_by do |bug_id, _pred_runs|
        #   bugs[bug_id]&.line_hunks&.then do
        #     _1 || 'other'
        #   end
        # end.each do |change_count, runs|
        #   plausible_results, _failing_bugs = partition_runs(runs, options)
        #   z =
        #     if options[:only_passing]
        #       bugs.count { |bug| bug.change_count == change_count }.to_f
        #     else
        #       runs.size.to_f
        #     end
        #   result[:"plausibility_rate_line_hunks#{change_count}"] = (plausible_results.size / z).round(4)
        # end
      end

      def analyze_by_exception(report)
        @results.group_by_exception.each do |exception, results|
          name =
            if exception.nil?
              'no_exception'
            else
              exception
            end

          # plausible_results, _failing_bugs = runs.partition { |_bug_id, pred_runs|  pred_runs.any?{ |pr| pr.all? { _1['result'] == 'pass'}}}
          plausible_count = results.plausible_count
          report[:"plausibility_rate_#{name}"] = format_rate(plausible_count, results.size)
        end
      end

      def analyze_by_label(report)
        label_length = options[:label_length]
        label_counts = bug_label_counts(label_length)
        plausible_label_counts = plausible_label_counts(@results.where_any_plausible_candidate, label_counts, label_length)

        label_counts.each do |label, count|
          plausible_count = plausible_label_counts.fetch(label, 0)
          report[:"plausibility_rate_#{label}"] = format_rate(plausible_count, count)
        end
      end

      def analyze_weak_strong_points(report)
        label_counts = bug_label_counts
        label_counts_sum = label_counts.sum { |_label, count| count }.to_f
        # label_counts = all_labels.transform_values { [_1 / all_labels_sum, _1] }
        plausible_label_counts = plausible_label_counts(@results.where_any_plausible_candidate, label_counts)

        plausible_label_counts_sum = plausible_label_counts.sum { |_label, count| count }.to_f
        # plausible_label_counts = plausible_label_counts.map { |k, v| [k, [v / plausible_label_counts_sum, v]] }.to_h

        scores = label_counts.map do |label, count|
          rel_freq = count / label_counts_sum
          plausible_count = plausible_label_counts.fetch(label, 0)
          plausible_rel_freq = plausible_count / plausible_label_counts_sum

          r = plausible_rel_freq / rel_freq

          [label, [r, plausible_count, count]]
        end

        if @options[:strong_points]
          best_labels = scores.sort_by { |_label, freqs| [-freqs[0], -freqs[-1]] }.take(15).to_h
          report[:strong_points] = best_labels
        end

        if @options[:weak_points]
          worst_labels = scores.sort_by { |_label, freqs| [freqs[0], -freqs[-1]] }.take(15).to_h
          report[:weak_points] = worst_labels
        end
        report[:no_labels] = scores.assoc('no_label')[1]
      end

      def label_for_length(label, length)
        return label if length.nil?
        label.split('.', length + 1)[...length].join('.')
      end

      def bug_label_counts(label_length)
        label_counts = Hash.new { |h, k| h[k] = 0 }
        @bugs.each do |bug|
          labels = bug&.labels
          if labels.nil? || labels.empty?
            label_counts['no_label'] += 1
          else
            labels.each do |label|
              label_counts[label_for_length(label, label_length)] += 1
            end
          end
        end

        # Remove low-frequency labels
        label_counts.delete_if { |_label, count| count < 30 }
        label_counts
      end

      def plausible_label_counts(plausible_results, label_counts, label_length)
        plausible_label_counts = Hash.new { |h, k| h[k] = 0 }

        plausible_results.each_bug do |bug|
          labels = bug&.labels
          if labels.nil? || labels.empty?
            plausible_label_counts['no_label'] += 1
          else
            labels.each do |label|
              plausible_label_counts[label_for_length(label, label_length)] += 1
            end
          end
        end

        # only keep frequent labels
        plausible_label_counts.delete_if { |label, _count| !label_counts.key? label }
        plausible_label_counts
      end

    end
  end
end
