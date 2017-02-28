module ThePolicyMachine
  module Generators
    class AddLogicalLinksTableGenerator < Rails::Generators::Base
      source_root File.expand_path('../../../migrations', __FILE__)

      def generate_add_logical_links_table_migration
        timestamp = Time.now.utc.strftime("%Y%m%d%H%M%S")
        copy_file('add_logical_links_table.rb', "db/migrate/#{timestamp}_add_logical_links_table.rb")
      end
    end
  end
end
