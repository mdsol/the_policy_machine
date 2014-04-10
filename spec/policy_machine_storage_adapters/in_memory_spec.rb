require 'spec_helper'
require 'policy_machine_storage_adapters/in_memory'

describe PolicyMachineStorageAdapter::InMemory do
  it_behaves_like 'a policy machine storage adapter with required public methods'
  it_behaves_like 'a policy machine storage adapter'
  
  describe 'find_all_of_type' do
    let(:policy_machine_storage_adapter) { described_class.new }
  end
end

describe 'PolicyMachine integration with PolicyMachineStorageAdapter::InMemory' do
  it_behaves_like 'a policy machine' do
    let(:policy_machine) { PolicyMachine.new(:name => 'in memory PM', :storage_adapter => PolicyMachineStorageAdapter::InMemory) }
  end    
end
