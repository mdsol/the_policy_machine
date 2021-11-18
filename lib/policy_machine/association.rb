module PM
  class Association
    attr_accessor :user_attribute, :operation_set, :object_attribute

    def initialize(stored_user_attribute, stored_operation_set, stored_object_attribute, pm_storage_adapter)
      @user_attribute = PM::PolicyElement.convert_stored_pe_to_pe(
        stored_user_attribute,
        pm_storage_adapter,
        PM::UserAttribute
      )

      @operation_set = PM::PolicyElement.convert_stored_pe_to_pe(
        stored_operation_set,
        pm_storage_adapter,
        PM::OperationSet
      )

      @object_attribute = PM::PolicyElement.convert_stored_pe_to_pe(
        stored_object_attribute,
        pm_storage_adapter,
        PM::ObjectAttribute
      )
    end

    # Create an association given persisted policy elements
    #
    def self.create(user_attribute_pe, operation_set, object_attribute_pe, policy_machine_uuid, pm_storage_adapter)
      # argument errors for user_attribute_pe
      unless user_attribute_pe.is_a?(PM::UserAttribute)
        raise(ArgumentError,
          'user_attribute_pe must be a UserAttribute.')
      end
      unless user_attribute_pe.policy_machine_uuid == policy_machine_uuid
        raise(ArgumentError, "user_attribute_pe must be in policy machine with uuid #{policy_machine_uuid}")
      end

      # argument errors for operation_set
      raise(ArgumentError, 'operation_set must be an OperationSet') unless operation_set.is_a?(PM::OperationSet)
      unless operation_set.policy_machine_uuid == policy_machine_uuid
        raise(ArgumentError, "operation_set must be in policy machine with uuid #{policy_machine_uuid}")
      end

      # argument errors for object_attribute_pe
      unless object_attribute_pe.is_a?(PM::ObjectAttribute)
        raise(ArgumentError,
          'object_attribute_pe must be an ObjectAttribute.')
      end
      unless object_attribute_pe.policy_machine_uuid == policy_machine_uuid
        raise(ArgumentError, "object_attribute_pe must be in policy machine with uuid #{policy_machine_uuid}")
      end

      pm_storage_adapter.add_association(
        user_attribute_pe.stored_pe,
        operation_set.stored_pe,
        object_attribute_pe.stored_pe
      )
    end
  end
end
