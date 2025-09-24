require 'run_bug_run/program'
require 'active_support/core_ext/hash/indifferent_access'
require 'active_support/concern'

module RunBugRun
  module Parsing
    extend ActiveSupport::Concern

    TREE_SITTER_CLASSES = {
      c: 'TreeSitter::C',
      cpp: 'TreeSitter::Cpp',
      javascript: 'TreeSitter::Javascript',
      java: 'TreeSitter::Java',
      ruby: 'TreeSitter::Ruby',
      python: 'TreeSitter::Python',
      php: 'TreeSitter::PhpOnly',
      go: 'TreeSitter::Go',
      c_sharp: 'TreeSitter::CSharp'
    }.with_indifferent_access.freeze

    class_methods do
      def parse(code, language)
        require 'tree_sitter'
        require 'tree_sitter/diff'
        if language == 'php'
          require "tree_sitter/php_only"
        else
          require "tree_sitter/#{language}"
        end

        cls ||= TREE_SITTER_CLASSES.fetch(language).constantize
        cls.parse(code, attach: true)
      end
    end

    def parse(version) = self.class.parse(self.code(version), language)

  end
end