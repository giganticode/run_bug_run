class AddActiveToBugsAndTests < ActiveRecord::Migration[7.1]
  def change
    add_column :bugs, :active, :boolean, default: true, null: false
    add_column :tests, :active, :boolean, default: true, null: false
    add_index :bugs, :active, where: 'active' 
    add_index :tests, :active, where: 'active'
  end
end
