require 'spec_helper'
require 'policy_machine_storage_adapters/in_memory'

describe PolicyMachineStorageAdapter::InMemory do
  it_behaves_like 'a policy machine storage adapter with required public methods'
  it_behaves_like 'a policy machine storage adapter'
  
  describe 'find_all_of_type' do
    let(:policy_machine_storage_adapter) { described_class.new }
    
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
        results = policy_machine_storage_adapter.find_all_of_type_object(color: 'red')
        results.first.unique_identifier.should == "uuid_0"
        results.last.unique_identifier.should == "uuid_9"
      end
      
      it 'defaults to page 1 if no page' do
        results = policy_machine_storage_adapter.find_all_of_type_object(color: 'red', per_page: 3)
        results.first.unique_identifier.should == "uuid_0"
        results.last.unique_identifier.should == "uuid_2"
      end

      it 'raises if you try to inject a where clause' do
        expect { policy_machine_storage_adapter.find_all_of_type_object(where: 'custom_query') }.to raise_error
      end
    end
  end
end

describe 'PolicyMachine integration with PolicyMachineStorageAdapter::InMemory' do
  it_behaves_like 'a policy machine' do
    let(:policy_machine) { PolicyMachine.new(:name => 'in memory PM', :storage_adapter => PolicyMachineStorageAdapter::InMemory) }
  end    
end
