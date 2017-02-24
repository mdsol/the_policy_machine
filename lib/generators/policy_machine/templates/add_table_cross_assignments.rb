class AddTableCrossAssignments < ActiveRecord::Migration
  def change

    create_table :cross_assignments do |t|
      t.integer :parent_id, null: false
      t.integer :child_id, null: false
      t.string :parent_policy_machine_uuid
      t.string :child_policy_machine_uuid
    end
    add_index :cross_assignments, [:parent_id, :child_id], unique: true
    add_index :cross_assignments, [:child_id]

  end
end
