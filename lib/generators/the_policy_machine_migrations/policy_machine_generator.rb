require 'rails/generators/active_record/migration/migration_generator'

class PolicyMachineGenerator < ::ActiveRecord::Generators::MigrationGenerator
  desc "Create a migration to store Policy Machine elements in your database"

  source_root File.expand_path('../templates', __FILE__)

  def initialize(*args)
    args[0] = ['generate_policy_machine', 'add_cross_table_assignments']
    super(*args)
  end

end
