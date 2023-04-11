require 'strscan'
require 'bigdecimal'

module RunBugRun
  class SubmissionOutputMatcher
    class OutputParser
      class ParseError < StandardError; end

      def initialize(output, strict: false)
        @output = output
        @s = StringScanner.new output
        @strict = strict
      end

      def parse
        lines = []
        lines << parse_line while @s.rest?

        lines
      end

      def parse_line
        line = []

        loop do
          skip
          # p ['debug', @s.peek(10)]
          break if end_of_line?
          skip
          element = parse_element
          raise ParseError, "failed to match element at '#{@s.peek(10)}'" if element.nil?
          line << element if element
        end

        line
      end

      def skip
        @s.skip(/[ \t\r\f\v]+/)
      end

      def end_of_line?
        @s.eos? || @s.scan(/\n/)
      end

      def parse_element
        if (n = parse_number)
          return n
        end

        @s.scan(/[^\s]+/)
      end

      # def parse_separator
      #   return s if (s = @s.scan(/(;|,)/))
      # end

      def parse_number
        if (number = @s.scan(/-?\d+(?:\.\d+)?/))
          if @strict && number =~ /^-?\d+?$/
            Integer(number)
          else
            BigDecimal(number)
          end
        end
      end
    end

    DEFAULT_FLOAT_EPS = 1e-4
    FLOAT_EPS = {
      # P02400: the description states abs. error <= 1e-5, however, we see
      # accepted submissions with errors slightly above that, so increasing slightly
      'p02400' => 1e-5,
      'p02008' => 1e-6,
      'p03882' => 1e-9,
      'p02805' => 1e-6,
      'p03585' => 1e-9,
      'p03619' => 1e-11,
      'p01562' => 1e-6,
      'p03428' => 1e-5,
      'p01837' => 1e-6,
      'p03135' => 1e-3,
      'p02764' => 1e-6,
      'p03888' => 1e-6,
      'p03110' => 1e-5,
      'p03901' => 1e-6,
      'p01836' => 1e-8,
      'p00973' => 1e-6,
      'p03043' => 1e-9,
      'p01948' => 1e-6,
      'p01800' => 1e-6,
      'p03304' => 1e-6,
      'p01704' => 1e-4,
      'p03001' => 1e-9,
      'p02072' => 1e-3,
      'p02897' => 1e-6,
      'p03754' => 1e-6,
      'p02731' => 1e-6,
      'p03879' => 1e-9,
      'p02677' => 1e-9,
      'p03953' => 1e-9,
      'p02894' => 1e-9,
      'p02705' => 1e-2,
      'p01825' => 1e-6,
      'p03514' => 1e-9,
      'p01672' => 1e-8,
      'p02882' => 1e-6,
      'p03881' => 1e-9,
      'p02075' => 1e-9,
      'p00988' => 1e-7,
      'p03744' => 1e-6,
      'p01685' => 1e-6,
      'p03872' => 1e-9,
      'p01703' => 1e-8, #FIXME: states relative error only!!
      'p03869' => 1e-9,
      'p02884' => 1e-6,
      'p03866' => 1e-9,
      'p02780' => 1e-6,
      'p01568' => 1e-6,
      'p01705' => 1e-4,
      'p01576' => 1e-8,
      'p02935' => 1e-5,
      'p03004' => 1e-9,
      'p02011' => 1e-6,
      'p01708' => 1e-2,
      'p03776' => 1e-6,
      'p02934' => 1e-5,
      'p01363' => 1e-6,
      'p01510' => 1e-9,
      'p03871' => 1e-9,
      'p02379' => 1e-4
    }.freeze

    def self.match?(expected_output, actual_output, problem_id)
      return false if actual_output.nil?

      expected_output = expected_output.chomp
      actual_output = actual_output.chomp
      return true if expected_output == actual_output

      expected_parsed = OutputParser.new(expected_output).parse
      actual_parsed = OutputParser.new(actual_output).parse

      return false if expected_parsed.size != actual_parsed.size

      # p expected_parsed
      # p actual_parsed

      float_eps = FLOAT_EPS.fetch(problem_id, DEFAULT_FLOAT_EPS)

      expected_parsed.zip(actual_parsed).all? do |expected_line, actual_line|
        next false if expected_line.size != actual_line.size

        expected_line.zip(actual_line).all? do |expected_element, actual_element|
          if expected_element.is_a?(BigDecimal) && actual_element.is_a?(BigDecimal)
            (actual_element - expected_element).abs <= float_eps
          else
            actual_element == expected_element
          end
        end
      end
    end
  end
end