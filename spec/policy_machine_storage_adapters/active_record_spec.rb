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

        it 'uses a custom where clause when the where key is present' do
          policy_machine_storage_adapter.add_object('some_uuid1', 'some_policy_machine_uuid1')
          policy_machine_storage_adapter.add_object('some_uuid2', 'some_policy_machine_uuid1', color: 'red')
          policy_machine_storage_adapter.add_object('some_uuid3', 'some_policy_machine_uuid1', color: 'blue')
          policy_machine_storage_adapter.find_all_of_type_object(where: "unique_identifier LIKE '%uuid1'").should be_one
        end

        context 'pagination' do
          before do
            10.times {|i| policy_machine_storage_adapter.add_object("uuid_#{i}", 'some_policy_machine_uuid1', color: 'red') }
          end

          it 'paginates the results based on page and per_page' do
            results = policy_machine_storage_adapter.find_all_of_type_object(color: 'red', per_page: 2, page: 3)
            results.first.unique_identifier.should == "uuid_4"
            results.last.unique_identifier.should == "uuid_5"
          end

          # TODO: Investigate why this doesn't fail when not slicing params
          it 'does not paginate if no page or per_page' do
            results = policy_machine_storage_adapter.find_all_of_type_object(color: 'red').sort
            results.first.unique_identifier.should == "uuid_0"
            results.last.unique_identifier.should == "uuid_9"
          end

          it 'defaults to page 1 if no page' do
            results = policy_machine_storage_adapter.find_all_of_type_object(color: 'red', per_page: 3)
            results.first.unique_identifier.should == "uuid_0"
            results.last.unique_identifier.should == "uuid_2"
          end
        end
      end
    end

    describe 'method_missing' do

      before do
        @o1 = policy_machine_storage_adapter.add_object('some_uuid1','some_policy_machine_uuid1')
      end

      it 'calls super when the method is not an attribute' do
        expect {@o1.sabe}.to raise_error NameError
      end

      it 'retrieves the attribute value' do
        @o1.extra_attributes = {foo: 'bar'}
        @o1.foo.should == 'bar'
      end

    end

    context 'when there is a lot of data' do

      before do
        n = 20
        @pm = PolicyMachine.new(:name => 'ActiveRecord PM', :storage_adapter => PolicyMachineStorageAdapter::ActiveRecord)
        @u1 = @pm.create_user('u1')
        @op = @pm.create_operation('own')
        @user_attributes = (1..n).map { |i| @pm.create_user_attribute("ua#{i}") }
        @object_attributes = (1..n).map { |i| @pm.create_object_attribute("oa#{i}") }
        @objects = (1..n).map { |i| @pm.create_object("o#{i}") }
        @user_attributes.each { |ua| @pm.add_assignment(@u1, ua) }
        @object_attributes.product(@user_attributes) { |oa, ua| @pm.add_association(ua, Set.new([@op]), oa) }
        @object_attributes.zip(@objects) { |oa, o| @pm.add_assignment(o, oa) }
      end

      it 'does not have O(n) database calls' do
        #TODO: Find a way to count all database calls that doesn't conflict with ActiveRecord magic
        PolicyMachineStorageAdapter::ActiveRecord::Assignment.should_receive(:transitive_closure?).at_most(10).times
        @pm.is_privilege?(@u1, @op, @objects.first).should be
      end

    end

  end

  describe 'PolicyMachine integration with PolicyMachineStorageAdapter::ActiveRecord' do
    it_behaves_like 'a policy machine' do
      let(:policy_machine) { PolicyMachine.new(:name => 'ActiveRecord PM', :storage_adapter => PolicyMachineStorageAdapter::ActiveRecord) }
    end
  end
end
