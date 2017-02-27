class AddCrossAssignmentsTable < ActiveRecord::Migration
  def change
    create_table :cross_assignments do |t|
      t.integer :cross_parent_id, null: false
      t.integer :cross_child_id, null: false
      t.string :cross_parent_policy_machine_uuid
      t.string :cross_child_policy_machine_uuid
    end

    add_index :cross_assignments, [:cross_parent_id, :cross_child_id], unique: true
    add_index :cross_assignments, [:cross_child_id]
  end
end
