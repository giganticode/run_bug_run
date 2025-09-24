class ImproveIndexes < ActiveRecord::Migration[7.1]
  def change
    remove_index :runs, :bug_id # this index is covered by larger index below
    remove_index :runs, column: %i[bug_id test_id candidate_index evaluation_id bug_version bug_variant], unique: true, name: 'index_evaluation_runs1'
    add_index :runs, %i[bug_id evaluation_id bug_version test_id bug_variant candidate_index], unique: true, name: 'index_runs1'

    remove_index :bugs, name: 'index_bugs_on_active', column: :active, where: 'active'

    # FIXME: [split language] would be nice too, hmm
    add_index :bugs, %i[language split], where: 'active'
  end
end
