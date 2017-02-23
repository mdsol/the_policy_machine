class GeneratePolicyMachine < ActiveRecord::Migration
  def change

    create_table :cross_assignments do |t|
      t.integer :parent_id, null: false
      t.integer :child_id, null: false
    end
    add_index :cross_assignments, [:parent_id, :child_id], unique: true
    add_index :cross_assignments, [:child_id]

  end
end
