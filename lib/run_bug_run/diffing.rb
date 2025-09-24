require 'run_bug_run/program'
require 'active_record'
require 'active_support/core_ext/hash/indifferent_access'

module RunBugRun
  module Diffing

    def tree_sitter_diff(buggy_code, fixed_code, ignore_whitespace: true, ignore_comments: true, output_equal: false, output_replace: false)
      return nil if buggy_code =~ /\A\s+\z/

      old = parse(:buggy)
      new = parse(:fixed)

      TreeSitter::Diff.diff(old.root_node, new.root_node, ignore_comments:, ignore_whitespace:, output_equal:, output_replace:)
    end

    def diffy_diff(buggy_code, fixed_code, format: :color)
      require 'diffy'
      Diffy::Diff.new(buggy_code, fixed_code).to_s(format)
    end

    def pq_similarity(other, version: :buggy, p: 3, q: 3, **options)
      a = parse(version).root_node.pq_profile(p, q, **options)
      b = other.parse(version).root_node.pq_profile(p, q, **options)

      if a.size > b.size
        t = a
        a = b
        b = t
      end

      i = 0

      intersection = a.count { b.include? _1 }
      intersection.to_f / (a.size + b.size - intersection)
    end

    def pq_profile_diff(buggy_code, fixed_code, p: 2, q: 3)
      tree_sitter_diff(buggy_code, fixed_code).each_with_object([]) do |change_set, profile|
        change_set.pq_profile(p, q, profile)
      end
    end

    def git_diff(buggy_code, fixed_code)
      require 'tempfile'
      require 'open3'
      Tempfile.create('buggy') do |buggy_file|
        Tempfile.create('fixed') do |fixed_file|
          buggy_file.print(buggy_code)
          buggy_file.flush
          buggy_file.close
          fixed_file.print(fixed_code)
          fixed_file.flush
          fixed_file.close

          output, status = Open3.capture2('git', '--no-pager', 'diff', '--no-index', '--word-diff=color', buggy_file.path, fixed_file.path)
          output
        end
      end
    end

  end
end