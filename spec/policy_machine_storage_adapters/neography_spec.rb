require 'spec_helper'
require 'policy_machine_storage_adapters/neography'

describe 'Neography' do
  before(:all) do
    stop_neo4j
    reset_neo4j
    start_neo4j    
  end
  before(:each) do
    clean_neo4j
  end
  after(:all) do
    stop_neo4j
  end
  
  describe PolicyMachineStorageAdapter::Neography do
    it_behaves_like 'a policy machine storage adapter with required public methods'
    it_behaves_like 'a policy machine storage adapter'
  end

  describe 'PolicyMachine integration with PolicyMachineStorageAdapter::Neography' do  
    it_behaves_like 'a policy machine' do
      let(:policy_machine) { PolicyMachine.new(:name => 'neography PM', :storage_adapter => PolicyMachineStorageAdapter::Neography) }    
    end
    
    describe '#assign' do
      # TODO:  storage adapters should be made tolerant to exceptions raised by underlying clients.
      it 'returns false when relationship cannot be created' do
        ::Neography::Relationship.stub(:create).and_return(nil)
        policy_machine_storage_adapter = PolicyMachineStorageAdapter::Neography.new
        src = policy_machine_storage_adapter.add_user('some_uuid1', 'some_policy_machine_uuid1')
        dst = policy_machine_storage_adapter.add_user_attribute('some_uuid2', 'some_policy_machine_uuid1')
        policy_machine_storage_adapter.assign(src, dst).should be_false
      end
    end

    describe 'find all' do
      it 'raises a NotImplementedError when active_record statements are added' do
        policy_machine_storage_adapter = PolicyMachineStorageAdapter::Neography.new
        expect { policy_machine_storage_adapter.find_all_of_type_object(where: "unique_identifier LIKE '%uuid1'") }.to raise_error
      end
    end
  end
end if neo4j_exists?

unless neo4j_exists?
  warn "Integration testing with neo4j requires that neo4j be installed in the gem's root directory"
end
