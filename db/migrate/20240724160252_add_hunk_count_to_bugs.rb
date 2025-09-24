class AddHunkCountToBugs < ActiveRecord::Migration[7.1]
  def change
    add_column :bugs, :hunk_count, :integer
  end
end
