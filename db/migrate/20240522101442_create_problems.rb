class CreateProblems < ActiveRecord::Migration[7.1]
  def change
    create_table :problems do |t|
      t.string :problem_id, index: {unique: true}
      t.text :text
    end
  end
end
