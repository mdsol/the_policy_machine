class AddInitialPolicyMachineTables < ActiveRecord::Migration[5.2]
  def change
    create_table :policy_elements do |t|
      t.string :unique_identifier, null: false
      t.string :policy_machine_uuid
      t.string :type, null: false
      t.text :extra_attributes
    end
    add_index :policy_elements, [:unique_identifier], unique: true
    add_index :policy_elements, [:type]

    create_table :policy_element_associations do |t|
      t.integer :user_attribute_id, null: false
      t.integer :object_attribute_id, null: false
    end
    add_index :policy_element_associations, %i[user_attribute_id object_attribute_id],
      name: 'index_pe_assocs_on_ua_and_oa'

    # TODO: If we end up not using this table in Postgres, make creating it conditional on the database type
    create_table :transitive_closure, id: false do |t|
      t.integer :ancestor_id, null: false
      t.integer :descendant_id, null: false
    end
    add_index :transitive_closure, %i[ancestor_id descendant_id], unique: true
    add_index :transitive_closure, [:descendant_id]

    create_table :assignments do |t|
      t.integer :parent_id, null: false
      t.integer :child_id, null: false
    end
    add_index :assignments, %i[parent_id child_id], unique: true
    add_index :assignments, [:child_id]
  end
end
