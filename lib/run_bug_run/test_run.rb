module RunBugRun
  TestRun = Struct.new(
    :status,
    :bug_id,
    :bug_version,
    :bug_variant,
    :test_id,
    :error_output,
    :output,
    :expected_output,
    keyword_init: true) do
      def pass? = status == 'pass'
  end
end