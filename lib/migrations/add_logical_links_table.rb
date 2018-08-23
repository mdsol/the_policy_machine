class AddLogicalLinksTable < ActiveRecord::Migration[5.0]
  def change
    create_table :logical_links do |t|
      t.integer :link_parent_id, null: false
      t.integer :link_child_id, null: false
      t.string :link_parent_policy_machine_uuid, null: false
      t.string :link_child_policy_machine_uuid, null: false
    end

    add_index :logical_links, [:link_parent_id, :link_child_id], unique: true
    add_index :logical_links, [:link_child_id]
  end
end
