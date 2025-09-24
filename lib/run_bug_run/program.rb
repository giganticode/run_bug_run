module RunBugRun
  Program = Struct.new(:code, :bug_id, :bug_variant, :candidate_index, :bug_version, :language, :main_class, :problem_id, keyword_init: true) do
    def filename_ext = Bug::FILENAME_EXTS.fetch language
  end

end