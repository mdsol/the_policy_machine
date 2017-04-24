require 'policy_machine'

# This class provides a template for creating your own Policy Machine
# Storage Adapter.  Simply copy this file and implement all public methods.
# Ensure correctness using the shared examples in
# 'spec/support/shared_examples_policy_machine_storage_adapter_spec.rb'.
# Ensure your adapter integrates properly with the policy machine using the shared
# examples in 'spec/support/shared_examples_policy_machine_spec.rb'.

module PolicyMachineStorageAdapter
  class Template

    ##
    # The following add_* methods store a policy element in the policy machine.
    # The unique_identifier identifies the element within the policy machine.
    # The policy_machine_uuid is the uuid of the containing policy machine.
    # Extra attributes should be persisted as metadata associated with the object.
    # Each method should return the persisted policy element.  Persisted policy
    # element objects should respond to each extra attribute key as well as the following methods:
    # * unique_identifier
    # * policy_machine_uuid
    # * persisted
    #
    def add_user(unique_identifier, policy_machine_uuid, extra_attributes = {})

    end
    def add_user_attribute(unique_identifier, policy_machine_uuid, extra_attributes = {})

    end
    def add_object(unique_identifier, policy_machine_uuid, extra_attributes = {})

    end
    def add_object_attribute(unique_identifier, policy_machine_uuid, extra_attributes = {})

    end
    def add_operation(unique_identifier, policy_machine_uuid, extra_attributes = {})

    end
    def add_policy_class(unique_identifier, policy_machine_uuid, extra_attributes = {})

    end

    ##
    # The following find_* methods should return an array of persisted
    # policy elements of the given type (e.g. user or object_attribute) and extra attributes.
    # If no such persisted policy elements are found, the empty array should
    # be returned.
    #
    def find_all_of_type_user(options = {})

    end
    def find_all_of_type_user_attribute(options = {})

    end
    def find_all_of_type_object(options = {})

    end
    def find_all_of_type_object_attribute(options = {})

    end
    def find_all_of_type_operation(options = {})

    end
    def find_all_of_type_policy_class(options = {})

    end

    ##
    # Assign src to dst in policy machine.
    # The two policy elements must be persisted policy elements; otherwise the method should raise
    # an ArgumentError.
    # Returns true if the assignment occurred, false otherwise.
    #
    def assign(src, dst)

    end

    ##
    # Connects two policy elements across different policy machines.
    # This is used for logical relationships outside of the policy machine formalism, such as the
    # relationship between a class of operable and a specific instance of it.
    #
    def link(src, dst)

    end

    ##
    # Determine if there is a path from src to dst in the policy machine.
    # The two policy elements must be persisted policy elements; otherwise the method should raise
    # an ArgumentError.
    # Returns true if there is a such a path and false otherwise.
    # Should return true if src == dst
    #
    def connected?(src, dst)

    end

    ##
    # Determine if there is a path from src to dst in different policy machines.
    # The two policy elements must be persisted policy elements; otherwise the method should raise
    # an ArgumentError.
    # Returns true if there is a such a path and false otherwise.
    # Should return false if src == dst
    #
    def linked?(src, dst)

    end

    ##
    # Disconnect two policy elements in the machine
    # The two policy elements must be persisted policy elements; otherwise the method should raise
    # an ArgumentError.
    # Returns true if unlink occurred and false otherwise.
    # Generally, false will be returned if the assignment didn't exist in the PM in the
    # first place.
    #
    def unassign(src, dst)

    end

    ##
    # Disconnects two policy elements in different machines.
    # Returns true if the unlink succeeds or false otherwise.
    # This is used for logical relationships outside of the policy machine formalism, such as the
    # relationship between a class of operable and a specific instance of it.
    #
    def unlink(src, dst)

    end

    ##
    # Remove a persisted policy element. This should remove its assignments and
    # associations but must not cascade to any connected policy elements.
    # Returns true if the delete succeeded.
    #
    def delete(element)

    end

    ##
    # Update the extra_attributes of a persisted policy element.
    # This should only affect attributes corresponding to the keys passed in.
    # Returns true if the update succeeded or was redundant.
    #
    def update(element, changes_hash)

    end

    ##
    # Determine if the given node is in the policy machine or not.
    # Returns true or false accordingly.
    #
    def element_in_machine?(pe)

    end

    ##
    # Add the given association to the policy map.  If an association between user_attribute
    # and object_attribute already exists, then replace it with that given in the arguments.
    # Returns true if the association was added and false otherwise.
    #
    def add_association(user_attribute, set_of_operation_objects, object_attribute, policy_machine_uuid)

    end

    ##
    # Return an array of all associations in which the given operation is included.
    # Each element of the array should itself be an array in which the first element
    # is the user_attribute member of the association, the second element is a
    # Ruby Set, each element of which is an operation, the third element is the
    # object_attribute member of the association.
    # If no associations are found then the empty array should be returned.
    #
    def associations_with(operation)

    end

    ##
    # Return array of all policy classes which contain the given object_attribute (or object).
    # Return empty array if no such policy classes found.
    def policy_classes_for_object_attribute(object_attribute)

    end

    ##
    # Return array of all user attributes which contain the given user.
    # Return empty array if no such user attributes are found.
    def user_attributes_for_user(user)
    end

    ##
    # Execute the passed-in block transactionally: any error raised out of the block causes
    # all the block's changes to be rolled back. Should raise NotImplementedError if the
    # persistence layer does not support this.
    def transaction

    end

    ## Optimized version of PolicyMachine#scoped_privileges
    # Return all operations the user has on the object
    # Optional: only add this method if you can do it better than policy_machine.rb
    def scoped_privileges(user_or_attribute, object_or_attribute)

    end

    # Optimized version of PolicyMachine#accessible_objects
    # Return all objects the user has the given operation on
    # Optional: only add this method if you can do it better than policy_machine.rb
    def accessible_objects(user_or_attribute, operation, options = {})
    end

  end
end
