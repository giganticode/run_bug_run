class AddTokenCountToBugs < ActiveRecord::Migration[7.1]
  def change
    add_column :bugs, :token_count, :integer
  end
end
