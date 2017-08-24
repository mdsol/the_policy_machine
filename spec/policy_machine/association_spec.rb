require 'spec_helper'

describe PM::Association do

  describe '#create' do
    before do
      @policy_machine = PolicyMachine.new
      @object_attribute = @policy_machine.create_object_attribute('OA name')
      @operation1 = @policy_machine.create_operation('read')
      @operation2 = @policy_machine.create_operation('write')
      @operation_set = @policy_machine.create_operation_set('reader_writer')
      @user_attribute = @policy_machine.create_user_attribute('UA name')

      @policy_machine.add_assignment(@operation_set, @operation1)
      @policy_machine.add_assignment(@operation_set, @operation2)

      other_pm = PolicyMachine.new
      @other_oa = other_pm.create_object_attribute('UA other')
      @other_op = other_pm.create_operation('delete')
    end

    it 'raises when the first argument is not a user attribute' do
      expect{ PM::Association.create(@object_attribute, @operation_set, @object_attribute, @policy_machine.uuid, @policy_machine.policy_machine_storage_adapter) }.
        to raise_error(ArgumentError, "user_attribute_pe must be a UserAttribute.")
    end

    it 'raises when the first argument is not in given policy machine' do
      expect{ PM::Association.create(@user_attribute, @operation_set, @object_attribute, "blah", @policy_machine.policy_machine_storage_adapter) }.
        to raise_error(ArgumentError, "user_attribute_pe must be in policy machine with uuid blah")
    end

    it 'raises when the second argument is not an object attribute' do
      expect{ PM::Association.create(@user_attribute, @operation_set, "abc", @policy_machine.uuid, @policy_machine.policy_machine_storage_adapter) }.
        to raise_error(ArgumentError, "object_attribute_pe must be an ObjectAttribute.")
    end

    it 'raises when the second argument is not in given policy machine' do
      expect{ PM::Association.create(@user_attribute, @operation_set, @other_oa, @policy_machine.uuid, @policy_machine.policy_machine_storage_adapter) }.
        to raise_error(ArgumentError, "object_attribute_pe must be in policy machine with uuid #{@policy_machine.uuid}")
    end
  end
end
