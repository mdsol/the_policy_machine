class UpdatePolicyElementAssociationsTable < ActiveRecord::Migration[5.2]
  def change
    add_column :policy_element_associations, :operation_set_id, :integer
    add_index :policy_element_associations,
      %i[user_attribute_id object_attribute_id operation_set_id],
      unique: true,
      where: 'operation_set_id IS NOT NULL',
      name: 'index_policy_element_associations_on_unique_triple' # generated name is too long
  end
end
