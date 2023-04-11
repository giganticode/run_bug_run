require 'csv'
require 'stringio'
require 'zlib'

require 'run_bug_run/json_utils'
require 'run_bug_run/cli/candidate_visualizer'

module RunBugRun
  module CLI
    class Vis < SubCommand
      desc 'candidates EVAL_OUTPUT', 'plots candidate evaluation results'
      method_option :o, desc: 'Output filename', type: :string, required: true
      method_option :languages, desc: 'languages to evaluate (defaults to all)', type: :array,
                                default: RunBugRun::Bugs::ALL_LANGUAGES.map(&:to_s)
      def candidates(output_filename)
        output = JSONUtils.load_file output_filename, symbolize_names: false
        visualizer = CandidateVisualizer.new(output, options)
        visualizer.render!
      end
    end
  end
end
