module PM
  class Association
    attr_accessor :user_attribute
    attr_accessor :set_of_operation_objects
    attr_accessor :operation_set
    attr_accessor :object_attribute

    def initialize(stored_user_attribute, stored_set_of_operation_objects, stored_operation_set, stored_object_attribute, pm_storage_adapter)
      @user_attribute = PM::PolicyElement.convert_stored_pe_to_pe(
        stored_user_attribute,
        pm_storage_adapter,
        PM::UserAttribute
      )

      @set_of_operation_objects = Set.new
      stored_set_of_operation_objects.each do |stored_op|
        op = PM::PolicyElement.convert_stored_pe_to_pe(
          stored_op,
          pm_storage_adapter,
          PM::Operation
        )
        @set_of_operation_objects << op
      end

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

    # Returns true if the operation set of this association includes the given operation.
    #
    def includes_operation?(operation)
      # Note:  set_of_operation_objects.member? isn't calling PM::PolicyElement ==
      set_of_operation_objects.any?{ |op| op == operation }
    end

    # Create an association given persisted policy elements
    #
    def self.create(user_attribute_pe, set_of_operation_objects, operation_set, object_attribute_pe, policy_machine_uuid, pm_storage_adapter)
      # argument errors for user_attribute_pe
      raise(ArgumentError, "user_attribute_pe must be a UserAttribute.") unless user_attribute_pe.is_a?(PM::UserAttribute)
      unless user_attribute_pe.policy_machine_uuid == policy_machine_uuid
        raise(ArgumentError, "user_attribute_pe must be in policy machine with uuid #{policy_machine_uuid}")
      end

      # argument errors for set_of_operation_objects
      raise(ArgumentError, "set_of_operation_objects must be a Set of Operations") unless set_of_operation_objects.is_a?(Set)
      raise(ArgumentError, "set_of_operation_objects must not be empty") if set_of_operation_objects.empty?
      set_of_operation_objects.each do |op|
        unless op.is_a?(PM::Operation)
          raise(ArgumentError, "expected #{op} to be PM::Operation; got #{op.class}")
        end
        unless op.policy_machine_uuid == policy_machine_uuid
          raise(ArgumentError, "expected #{op.unique_identifier} to be in Policy Machine with uuid #{policy_machine_uuid}; got #{op.policy_machine_uuid}")
        end
      end

      #argument errors for operation_set
      raise(ArgumentError, "operation_set must be an OperationSet") unless operation_set.is_a?(PM::OperationSet)
      unless operation_set.policy_machine_uuid == policy_machine_uuid
        raise(ArgumentError, "operation_set must be in policy machine with uuid #{policy_machine_uuid}")
      end

      # argument errors for object_attribute_pe
      raise(ArgumentError, "object_attribute_pe must be an ObjectAttribute.") unless object_attribute_pe.is_a?(PM::ObjectAttribute)
      unless object_attribute_pe.policy_machine_uuid == policy_machine_uuid
        raise(ArgumentError, "object_attribute_pe must be in policy machine with uuid #{policy_machine_uuid}")
      end

      pm_storage_adapter.add_association(
        user_attribute_pe.stored_pe,
        Set.new(set_of_operation_objects.map(&:stored_pe)),
        operation_set,
        object_attribute_pe.stored_pe,
        policy_machine_uuid
      )
    end
  end
end
