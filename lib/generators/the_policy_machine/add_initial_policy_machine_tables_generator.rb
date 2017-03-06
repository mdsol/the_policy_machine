module ThePolicyMachine
  module Generators
    class AddInitialPolicyMachineTablesGenerator < Rails::Generators::Base
      source_root File.expand_path('../../../migrations', __FILE__)

      def generate_add_initial_policy_machine_tables_migration
        timestamp = Time.now.utc.strftime("%Y%m%d%H%M%S")
        copy_file('add_initial_policy_machine_tables.rb', "db/migrate/#{timestamp}_add_initial_policy_machine_tables.rb")
      end
    end
  end
end
