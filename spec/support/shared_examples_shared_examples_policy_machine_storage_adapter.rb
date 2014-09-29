# Policy Machines are directed acyclic graphs (DAG).  These shared examples describe the
# API for these DAGs, which could be persisted in memory, in a graph database, etc.

require_relative 'storage_adapter_helpers.rb'

shared_examples "a policy machine storage adapter" do
  let(:policy_machine_storage_adapter) { described_class.new }

  PolicyMachine::POLICY_ELEMENT_TYPES.each do |pe_type|
    describe "#add_#{pe_type}" do
      it 'stores the policy element' do
        src = policy_machine_storage_adapter.send("add_#{pe_type}", 'some_uuid', 'some_policy_machine_uuid')
        policy_machine_storage_adapter.element_in_machine?(src).should be_true
      end

      it 'returns the instantiated policy element with persisted attribute set to true' do
        node = policy_machine_storage_adapter.send("add_#{pe_type}", 'some_uuid', 'some_policy_machine_uuid')
        node.persisted.should be_true
      end
    end

    describe "find_all_of_type_#{pe_type}" do
      it 'returns empty array if nothing found' do
        policy_machine_storage_adapter.send("find_all_of_type_#{pe_type}").should == []
      end

      it 'returns array of found policy elements of given type if one is found' do
        node = policy_machine_storage_adapter.send("add_#{pe_type}", 'some_uuid', 'some_policy_machine_uuid')
        policy_machine_storage_adapter.send("find_all_of_type_#{pe_type}").should == [node]
      end

      it 'returns array of found policy elements of given type if more than one is found' do
        node1 = policy_machine_storage_adapter.send("add_#{pe_type}", 'some_uuid1', 'some_policy_machine_uuid')
        node2 = policy_machine_storage_adapter.send("add_#{pe_type}", 'some_uuid2', 'some_policy_machine_uuid')
        policy_machine_storage_adapter.send("find_all_of_type_#{pe_type}").should match_array([node1, node2])
      end
      
      context 'case sensitivity' do
        before do
          ['abcde', 'object1'].each do |name| 
            policy_machine_storage_adapter.add_object("#{name}_uuid", 'some_policy_machine_uuid', name: name) 
          end
        end

        around { |test| Kernel.silence_warnings{test.run} }
        
        it 'finds with case sensitivity by default' do
          expect(policy_machine_storage_adapter.find_all_of_type_object(name: 'ABCDE')).to eq([])
          expect(policy_machine_storage_adapter.find_all_of_type_object(name: 'oBJECt1')).to eq([])
        end
        
        it 'finds without case sensitivity if the option is passed' do
          expect(policy_machine_storage_adapter.find_all_of_type_object(name: 'ABCDE', ignore_case: true).first.unique_identifier).to eq('abcde_uuid')
          expect(policy_machine_storage_adapter.find_all_of_type_object(name: 'oBJECt1', ignore_case: true).first.unique_identifier).to eq('object1_uuid')
        end
      end
    end
  end

  describe '#assign' do
    before do
      @src = policy_machine_storage_adapter.add_user('some_uuid1', 'some_policy_machine_uuid1')
      @dst = policy_machine_storage_adapter.add_user_attribute('some_uuid2', 'some_policy_machine_uuid1')
    end

    context 'source or destination node is of the Node type return by add_' do
      it 'assigns the nodes in one direction (from source to destination)' do
        policy_machine_storage_adapter.assign(@src, @dst)
        policy_machine_storage_adapter.connected?(@src, @dst).should be_true
      end

      it 'does not connect the nodes from destination to source' do
        policy_machine_storage_adapter.assign(@src, @dst)
        policy_machine_storage_adapter.connected?(@dst, @src).should be_false
      end

      it 'returns true' do
        policy_machine_storage_adapter.assign(@src, @dst).should be_true
      end
    end

    context 'source or destination node is not of the Node type return by add_' do
      it 'raises for source' do
        expect{ policy_machine_storage_adapter.assign(2, @dst) }.to raise_error(ArgumentError)
      end

      it 'raises for destination' do
        expect{ policy_machine_storage_adapter.assign(@src, "") }.to raise_error(ArgumentError)
      end
    end
  end

  describe '#connected?' do
    before do
      @src = policy_machine_storage_adapter.add_user('some_uuid1', 'some_policy_machine_uuid1')
      @dst = policy_machine_storage_adapter.add_user_attribute('some_uuid2', 'some_policy_machine_uuid1')

      @internal1 = policy_machine_storage_adapter.add_user_attribute('some_uuid2a', 'some_policy_machine_uuid1')
      @internal2 = policy_machine_storage_adapter.add_user_attribute('some_uuid2b', 'some_policy_machine_uuid1')
      @internal3 = policy_machine_storage_adapter.add_user_attribute('some_uuid2c', 'some_policy_machine_uuid1')

      policy_machine_storage_adapter.assign(@src, @internal1)
      policy_machine_storage_adapter.assign(@internal1, @internal3)
      policy_machine_storage_adapter.assign(@internal2, @internal1)
      policy_machine_storage_adapter.assign(@internal3, @dst)
    end

    context 'source or destination node is of the Node type return by add_node' do
      it 'returns true if source and destination nodes are connected' do
        policy_machine_storage_adapter.connected?(@src, @dst).should be_true
      end

      it 'returns false if source and destination nodes are not connected' do
        policy_machine_storage_adapter.connected?(@src, @internal2).should be_false
      end
    end

    context 'source or destination node is not of the Node type return by add_node' do
      it 'raises for source' do
        expect{ policy_machine_storage_adapter.connected?("", @dst) }.to raise_error(ArgumentError)
      end

      it 'raises for destination' do
        expect{ policy_machine_storage_adapter.connected?(@src, 6) }.to raise_error(ArgumentError)
      end
    end
  end

  describe '#unassign' do
    before do
      @src = policy_machine_storage_adapter.add_user('some_uuid1', 'some_policy_machine_uuid1')
      @dst = policy_machine_storage_adapter.add_user_attribute('some_uuid2', 'some_policy_machine_uuid1')
      policy_machine_storage_adapter.assign(@src, @dst)
    end

    context 'source or destination node is of the Node type return by add_' do
      it 'disconnects source node from destination node' do
        policy_machine_storage_adapter.unassign(@src, @dst)
        policy_machine_storage_adapter.connected?(@src, @dst).should be_false
      end

      it 'does not disconnect destination from source node if there is an assignment in that direction' do
        policy_machine_storage_adapter.assign(@dst, @src)
        policy_machine_storage_adapter.unassign(@src, @dst)
        policy_machine_storage_adapter.connected?(@dst, @src).should be_true
      end

      it 'returns true on successful disconnection' do
        policy_machine_storage_adapter.unassign(@src, @dst).should be_true
      end

      it "returns false on unsuccessful disconnection (if the nodes weren't connected in the first place')" do
        policy_machine_storage_adapter.unassign(@src, @dst)
        policy_machine_storage_adapter.unassign(@src, @dst).should be_false
      end
    end

    context 'source or destination node is not of the Node type return by add_node' do
      it 'raises for source' do
        expect{ policy_machine_storage_adapter.unassign(6, @dst) }.to raise_error(ArgumentError)
      end

      it 'raises for destination' do
        expect{ policy_machine_storage_adapter.unassign(false, @dst) }.to raise_error(ArgumentError)
      end
    end
  end

  describe '#element_in_machine?' do
    before do
      @pe = policy_machine_storage_adapter.add_user('some_uuid1', 'some_policy_machine_uuid1')
    end

    it 'returns true when element is in machine' do
      policy_machine_storage_adapter.element_in_machine?(@pe).should be_true
    end
  end

  describe '#add_association' do
    before do
      @ua = policy_machine_storage_adapter.add_user_attribute('some_ua', 'some_policy_machine_uuid1')
      @r = policy_machine_storage_adapter.add_operation('read', 'some_policy_machine_uuid1')
      @w = policy_machine_storage_adapter.add_operation('write', 'some_policy_machine_uuid1')
      @oa = policy_machine_storage_adapter.add_object_attribute('some_oa', 'some_policy_machine_uuid1')
    end

    it 'returns true' do
      policy_machine_storage_adapter.add_association(@ua, Set.new([@r, @w]), @oa, 'some_policy_machine_uuid1').should be_true
    end

    it 'stores the association' do
      policy_machine_storage_adapter.add_association(@ua, Set.new([@r, @w]), @oa, 'some_policy_machine_uuid1')
      assocs_with_r = policy_machine_storage_adapter.associations_with(@r)
      assocs_with_r.size == 1
      assocs_with_r[0][0].should == @ua
      assocs_with_r[0][1].to_a.should == [@r, @w]
      assocs_with_r[0][2].should == @oa

      assocs_with_w = policy_machine_storage_adapter.associations_with(@w)
      assocs_with_w.size == 1
      assocs_with_w[0][0].should == @ua
      assocs_with_w[0][1].to_a.should == [@r, @w]
      assocs_with_w[0][2].should == @oa
    end

    it 'overwrites a previously stored association' do
      policy_machine_storage_adapter.add_association(@ua, Set.new([@r, @w]), @oa, 'some_policy_machine_uuid1')
      policy_machine_storage_adapter.add_association(@ua, Set.new([@r]), @oa, 'some_policy_machine_uuid1')
      assocs_with_r = policy_machine_storage_adapter.associations_with(@r)
      assocs_with_r.size == 1
      assocs_with_r[0][0].should == @ua
      assocs_with_r[0][1].to_a.should == [@r]
      assocs_with_r[0][2].should == @oa

      policy_machine_storage_adapter.associations_with(@w).should == []
    end
  end

  describe '#associations_with' do
    before do
      @ua = policy_machine_storage_adapter.add_user_attribute('some_ua', 'some_policy_machine_uuid1')
      @ua2 = policy_machine_storage_adapter.add_user_attribute('some_other_ua', 'some_policy_machine_uuid1')
      @r = policy_machine_storage_adapter.add_operation('read', 'some_policy_machine_uuid1')
      @w = policy_machine_storage_adapter.add_operation('write', 'some_policy_machine_uuid1')
      @e = policy_machine_storage_adapter.add_operation('execute', 'some_policy_machine_uuid1')
      @oa = policy_machine_storage_adapter.add_object_attribute('some_oa', 'some_policy_machine_uuid1')
    end

    it 'returns empty array when given operation has no associated associations' do
      policy_machine_storage_adapter.associations_with(@r).should == []
    end

    it 'returns structured array when given operation has associated associations' do
      policy_machine_storage_adapter.add_association(@ua, Set.new([@w]), @oa, 'some_policy_machine_uuid1')
      policy_machine_storage_adapter.add_association(@ua2, Set.new([@w, @e]), @oa, 'some_policy_machine_uuid1')
      assocs_with_w = policy_machine_storage_adapter.associations_with(@w)

      assocs_with_w.size == 2
      assocs_with_w[0][0].should == @ua
      assocs_with_w[0][1].to_a.should == [@w]
      assocs_with_w[0][2].should == @oa
      assocs_with_w[1][0].should == @ua2
      assocs_with_w[1][1].to_a.should == [@w, @e]
      assocs_with_w[1][2].should == @oa

    end

  end

  describe '#policy_classes_for_object_attribute' do
    before do
      @oa = policy_machine_storage_adapter.add_object_attribute('some_oa', 'some_policy_machine_uuid1')
      @pc1 = policy_machine_storage_adapter.add_policy_class('some_pc1', 'some_policy_machine_uuid1')
      @pc2 = policy_machine_storage_adapter.add_policy_class('some_pc2', 'some_policy_machine_uuid1')
      @pc3 = policy_machine_storage_adapter.add_policy_class('some_pc3', 'some_policy_machine_uuid1')
    end

    it 'returns empty array if object is in no policy classes' do
      policy_machine_storage_adapter.policy_classes_for_object_attribute(@oa).should == []
    end

    it 'returns array of policy class(es) if object is in policy class(es)' do
      policy_machine_storage_adapter.assign(@oa, @pc1)
      policy_machine_storage_adapter.assign(@oa, @pc3)
      policy_machine_storage_adapter.policy_classes_for_object_attribute(@oa).should match_array([@pc1, @pc3])
    end

  end

  describe '#transaction' do
    it 'executes the block' do
      if_implements(policy_machine_storage_adapter, :transaction){}
      policy_machine_storage_adapter.transaction do
        @oa = policy_machine_storage_adapter.add_object_attribute('some_oa', 'some_policy_machine_uuid1')
        @pc1 = policy_machine_storage_adapter.add_policy_class('some_pc1', 'some_policy_machine_uuid1')
        policy_machine_storage_adapter.assign(@oa, @pc1)
      end
      policy_machine_storage_adapter.policy_classes_for_object_attribute(@oa).should == [@pc1]
    end

    it 'rolls back the block on error' do
      if_implements(policy_machine_storage_adapter, :transaction){}
      @oa = policy_machine_storage_adapter.add_object_attribute('some_oa', 'some_policy_machine_uuid1')
      @pc1 = policy_machine_storage_adapter.add_policy_class('some_pc1', 'some_policy_machine_uuid1')
      policy_machine_storage_adapter.assign(@oa, @pc1)
      expect do
        policy_machine_storage_adapter.transaction do
          @pc2 = policy_machine_storage_adapter.add_policy_class('some_pc2', 'some_policy_machine_uuid1')
          policy_machine_storage_adapter.assign(@oa, @pc2)
          policy_machine_storage_adapter.assign(@oa, :invalid_policy_class)
        end
      end.to raise_error(ArgumentError)
      policy_machine_storage_adapter.find_all_of_type_policy_class.should == [@pc1]
      policy_machine_storage_adapter.policy_classes_for_object_attribute(@oa).should == [@pc1]
    end
  end

end
