class RenameLabelsToLabelIdsInBugs < ActiveRecord::Migration[7.1]
  def change
    rename_column :bugs, :labels, :label_ids
  end
end
