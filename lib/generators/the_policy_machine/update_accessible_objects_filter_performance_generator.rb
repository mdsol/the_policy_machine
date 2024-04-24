module ThePolicyMachine
  module Generators
    class UpdateAccessibleObjectsFilterPerformanceGenerator < Rails::Generators::Base
      source_root File.expand_path('../../../migrations', __FILE__)

      def generate_update_accessible_objects_filter_performance_migration
        timestamp = Time.now.utc.strftime("%Y%m%d%H%M%S")
        copy_file('update_accessible_objects_filter_performance.rb', "db/migrate/#{timestamp}_update_accessible_objects_filter_performance.rb")
      end
    end
  end
end
