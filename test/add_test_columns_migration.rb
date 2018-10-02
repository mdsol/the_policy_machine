class AddTestColumns < ActiveRecord::Migration[5.2]
  def change
    add_column :policy_elements, :color, :string
    if ActiveRecord::Base.connection.class.name == 'ActiveRecord::ConnectionAdapters::PostgreSQLAdapter'
      add_column :policy_elements, :tags, 'text[]'
      add_column :policy_elements, :document, :jsonb, default: {}
    else
      add_column :policy_elements, :tags, :text
    end
  end
end
