class CreateEvaluations < ActiveRecord::Migration[7.0]
  def change
    create_table :evaluations do |t|
      t.string :name, null: false
      t.datetime :started_at, null: false
      t.datetime :ended_at, null: true
      t.index %i[name], unique: true

      t.timestamps
    end

    create_table :evaluation_runs do |t|
      t.references :evaluation, foreign_key: true, null: false
      t.integer :status, null: false
      t.references :bug, foreign_key: true, null: false
      t.integer :bug_version, null: false
      t.integer :bug_variant, null: false
      t.integer :candidate_index
      t.references :test, foreign_key: true, null: false
      t.text :error_output
      t.text :output

      t.index %i[bug_id test_id candidate_index evaluation_id bug_version bug_variant], unique: true, name: 'index_evaluation_runs1'

      t.timestamps
    end
  end
end
