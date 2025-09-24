class CreateTables < ActiveRecord::Migration[7.0]
  def change
    create_table :bugs do |t|
      t.text :buggy_code, null: false
      t.text :fixed_code, null: false
      t.string :problem_id, null: false
      t.string :user_id, null: false
      t.string :buggy_submission_id, null: false
      t.string :fixed_submission_id, null: false
      t.integer :language, null: false

      t.json :labels
      t.json :runtime_errors
      t.integer :change_count

      t.integer :split

      # Java only
      t.string :buggy_main_class
      t.string :fixed_main_class

      t.index %i[problem_id user_id buggy_submission_id fixed_submission_id], unique: true, name: 'index_bugs_uniq'

      t.timestamps
    end

    create_table :tests do |t|
      t.string :problem_id, null: false
      t.integer :test_id, null: false
      t.text :input
      t.text :output

      t.index %i[problem_id test_id], unique: true

      t.timestamps
    end

  end
end
