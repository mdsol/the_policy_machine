class GeneratePolicyMachine < ActiveRecord::Migration
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
    add_index :policy_element_associations, [:user_attribute_id, :object_attribute_id], name: 'index_pe_assocs_on_ua_and_oa'

    create_table :transitive_closure, id: false do |t|
      t.integer :ancestor_id, null: false
      t.integer :descendant_id, null: false
    end
    add_index :transitive_closure, [:ancestor_id, :descendant_id], unique: true
    add_index :transitive_closure, [:descendant_id]

    create_table :assignments do |t|
      t.integer :parent_id, null: false
      t.integer :child_id, null: false
    end
    add_index :assignments, [:parent_id, :child_id], unique: true
    add_index :assignments, [:child_id]

    create_table :operations_policy_element_associations, id: false do |t|
      t.integer :policy_element_association_id, null: false
      t.integer :operation_id, null: false
    end
    add_index :operations_policy_element_associations, [:policy_element_association_id, :operation_id], unique: true, name: 'index_pe_assoc_os_on_assoc_and_o'

  end
end
