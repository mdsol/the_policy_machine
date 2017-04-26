class UpdatePolicyElementAssociationsTable < ActiveRecord::Migration
  def change
    add_column :policy_element_associations, :operation_set_id, :integer
  end
end
