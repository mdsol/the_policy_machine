module ThePolicyMachine
  module Generators
    class AccessibleObjectsFunctionGenerator < Rails::Generators::Base
      source_root File.expand_path('../../../migrations', __FILE__)

      def generate_accessible_objects_function_migration
        timestamp = Time.now.utc.strftime("%Y%m%d%H%M%S")
        copy_file('accessible_objects_function.rb', "db/migrate/#{timestamp}_accessible_objects_function.rb")
      end
    end
  end
end
