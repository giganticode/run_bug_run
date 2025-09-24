class RenameEvaluationRunsToRuns < ActiveRecord::Migration[7.1]
  def change
    rename_table :evaluation_runs, :runs
  end
end
