module ThePolicyMachine
  module Generators
    class AccessibleObjectsForOperationsFunctionCteGenerator < Rails::Generators::Base
      source_root File.expand_path('../../../migrations', __FILE__)

      def generate_update_accessible_objects_filter_performance_migration
        timestamp = Time.now.utc.strftime("%Y%m%d%H%M%S")
        copy_file(
          'accessible_objects_for_operations_function_cte.rb',
          "db/migrate/#{timestamp}_accessible_objects_for_operations_function_cte.rb"
        )
      end
    end
  end
end
