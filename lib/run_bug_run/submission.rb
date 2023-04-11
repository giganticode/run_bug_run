module RunBugRun
  class Submission

    FILENAME_EXTS = {
      c: 'c',
      cpp: 'cpp',
      javascript: 'js',
      java: 'java',
      ruby: 'rb',
      python: 'py',
      php: 'php',
      go: 'go'
    }.freeze

    attr_reader :id, :code, :problem_id, :language, :main_class, :accepted, :errors

    def initialize(id:, code:, problem_id:, language:, main_class:, accepted:, errors: nil)
      @id = id
      @code = code
      @problem_id = problem_id
      @language = language.to_sym
      @main_class = main_class
      @accepted = accepted
      @errors = errors
    end

    def self.from_hash(hash)
      new(**hash)
    end

    def to_h
      {id:, code:, problem_id:, language:, main_class:, accepted:, errors:}
    end

    def accepted? = @accepted
    def filename_ext = FILENAME_EXTS.fetch language
  end
end