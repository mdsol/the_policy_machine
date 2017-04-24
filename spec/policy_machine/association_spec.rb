require 'spec_helper'

describe PM::Association do

  describe '#create' do
    before do
      @policy_machine = PolicyMachine.new
      @object_attribute = @policy_machine.create_object_attribute('OA name')
      @operation1 = @policy_machine.create_operation('read')
      @operation2 = @policy_machine.create_operation('write')
      @operation_set = Set.new [@operation1, @operation2]
      @user_attribute = @policy_machine.create_user_attribute('UA name')

      other_pm = PolicyMachine.new
      @other_oa = other_pm.create_object_attribute('UA other')
      @other_op = other_pm.create_operation('delete')
    end

    it 'raises when first argument is not a user attribute' do
      expect{ PM::Association.create(@object_attribute, @operation_set, @object_attribute, @policy_machine.uuid, @policy_machine.policy_machine_storage_adapter) }.
        to raise_error(ArgumentError, "user_attribute_pe must be a UserAttribute.")
    end

    it 'raises when first argument is not in given policy machine' do
      expect{ PM::Association.create(@user_attribute, @operation_set, @object_attribute, "blah", @policy_machine.policy_machine_storage_adapter) }.
        to raise_error(ArgumentError, "user_attribute_pe must be in policy machine with uuid blah")
    end

    it 'raises when second argument is not a set' do
      expect{ PM::Association.create(@user_attribute, 1, @object_attribute, @policy_machine.uuid, @policy_machine.policy_machine_storage_adapter) }.
        to raise_error(ArgumentError, "operation_set must be a Set of Operations")
    end

    it 'raises when second argument is empty set' do
      expect{ PM::Association.create(@user_attribute, Set.new, @object_attribute, @policy_machine.uuid, @policy_machine.policy_machine_storage_adapter) }.
        to raise_error(ArgumentError, "operation_set must not be empty")
    end

    it 'raises when second argument is a set in which at least one element is not a PM::Operation' do
      expect{ PM::Association.create(@user_attribute, Set.new([@operation1, 1]), @object_attribute, @policy_machine.uuid, @policy_machine.policy_machine_storage_adapter) }.
        to raise_error(ArgumentError, "expected 1 to be PM::Operation; got #{SmallNumber}")
    end

    it 'raises when second argument is a set in which at least one element is a PM::Operation which is in a different policy machine' do
      expect{ PM::Association.create(@user_attribute, Set.new([@other_op]), @object_attribute, @policy_machine.uuid, @policy_machine.policy_machine_storage_adapter) }.
        to raise_error(ArgumentError, "expected #{@other_op.unique_identifier} to be in Policy Machine with uuid #{@policy_machine.uuid}; got #{@other_op.policy_machine_uuid}")
    end

    it 'raises when third argument is not an object attribute' do
      expect{ PM::Association.create(@user_attribute, @operation_set, "abc", @policy_machine.uuid, @policy_machine.policy_machine_storage_adapter) }.
        to raise_error(ArgumentError, "object_attribute_pe must be an ObjectAttribute.")
    end

    it 'raises when third argument is not in given policy machine' do
      expect{ PM::Association.create(@user_attribute, @operation_set, @other_oa, @policy_machine.uuid, @policy_machine.policy_machine_storage_adapter) }.
        to raise_error(ArgumentError, "object_attribute_pe must be in policy machine with uuid #{@policy_machine.uuid}")
    end

  end

end
