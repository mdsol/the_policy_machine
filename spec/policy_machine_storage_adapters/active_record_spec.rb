require 'spec_helper'
require 'policy_machine_storage_adapters/active_record'
require 'database_cleaner'

DatabaseCleaner.strategy = :truncation

describe 'ActiveRecord' do

  before(:each) do
    Rails.cache.clear
    DatabaseCleaner.clean
  end

  describe PolicyMachineStorageAdapter::ActiveRecord do
    it_behaves_like 'a policy machine storage adapter with required public methods'
    it_behaves_like 'a policy machine storage adapter'
    let(:policy_machine_storage_adapter) { described_class.new }

    describe 'find_all_of_type' do

      it 'warns when filtering on an extra attribute' do
        policy_machine_storage_adapter.should_receive(:warn).once
        policy_machine_storage_adapter.find_all_of_type_user(foo: 'bar').should be_empty
      end

      context 'an extra attribute column has been added to the database' do

        it 'does not warn' do
          policy_machine_storage_adapter.should_not_receive(:warn)
          policy_machine_storage_adapter.find_all_of_type_user(color: 'red').should be_empty
        end

        it 'only returns elements that match the hash' do
          policy_machine_storage_adapter.add_object('some_uuid1', 'some_policy_machine_uuid1')
          policy_machine_storage_adapter.add_object('some_uuid2', 'some_policy_machine_uuid1', color: 'red')
          policy_machine_storage_adapter.add_object('some_uuid3', 'some_policy_machine_uuid1', color: 'blue')
          policy_machine_storage_adapter.find_all_of_type_object(color: 'red').should be_one
          policy_machine_storage_adapter.find_all_of_type_object(color: nil).should be_one
          policy_machine_storage_adapter.find_all_of_type_object(color: 'green').should be_none
          policy_machine_storage_adapter.find_all_of_type_object(color: 'blue').map(&:color).should eql(['blue'])
        end

      end

    end

  end

  describe 'PolicyMachine integration with PolicyMachineStorageAdapter::ActiveRecord' do
    it_behaves_like 'a policy machine' do
      let(:policy_machine) { PolicyMachine.new(:name => 'ActiveRecord PM', :storage_adapter => PolicyMachineStorageAdapter::ActiveRecord) }
    end
  end
end
