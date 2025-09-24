class AddWallTimeToEvaluationRuns < ActiveRecord::Migration[7.0]
  def change
    add_column :evaluation_runs, :wall_time, :decimal
  end
end
