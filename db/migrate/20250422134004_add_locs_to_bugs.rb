class AddLocsToBugs < ActiveRecord::Migration[7.1]
  def change
    add_column :bugs, :buggy_locs, :integer
    add_column :bugs, :fixed_locs, :integer

    # %w[buggy fixed].each do |version|
    #   %w[blank comment code].each do |type|
    #     add_column :bugs, :"#{version}_#{type}_line_count", :integer
    #   end
    # end
  end
end
