module ThePolicyMachine
  module Generators
    class UpdatePolicyElementAssociationsTableGenerator < Rails::Generators::Base
      source_root File.expand_path('../../../migrations', __FILE__)

      def generate_add_logical_links_table_migration
        timestamp = Time.now.utc.strftime("%Y%m%d%H%M%S")
        copy_file('update_policy_element_associations_table.rb', "db/migrate/#{timestamp}_update_policy_element_associations_table.rb")
      end
    end
  end
end
