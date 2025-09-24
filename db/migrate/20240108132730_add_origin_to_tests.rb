class AddOriginToTests < ActiveRecord::Migration[7.1]
  def change
    add_column :tests, :origin, :integer, default: 0, null: false
  end
end
