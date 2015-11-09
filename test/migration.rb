class AddTestColumns < ActiveRecord::Migration
  def change
    add_column :policy_elements, :color, :string
    if ActiveRecord::Base.connection.class.name == 'ActiveRecord::ConnectionAdapters::PostgreSQLAdapter'
      add_column :policy_elements, :tags, 'text[]'
    else
      add_column :policy_elements, :tags, :text
    end
  end
end
