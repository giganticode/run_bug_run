class AddSimilarProblemsToProblems < ActiveRecord::Migration[7.1]
  def change
    add_column :problems, :similar_problems, :jsonb
  end
end
