class AddColorToPolicyElement < ActiveRecord::Migration
  def change
    add_column :policy_elements, :color, :string
  end
end
