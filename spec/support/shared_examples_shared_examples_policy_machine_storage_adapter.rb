# Policy Machines are directed acyclic graphs (DAG).  These shared examples describe the
# API for these DAGs, which could be persisted in memory, in a graph database, etc.
require_relative 'storage_adapter_helpers.rb'

shared_examples "a policy machine storage adapter" do
  let(:policy_machine_storage_adapter) { described_class.new }

  PolicyMachine::POLICY_ELEMENT_TYPES.each do |pe_type|
    describe "#add_#{pe_type}" do
      it 'stores the policy element' do
        src = policy_machine_storage_adapter.send("add_#{pe_type}", 'some_uuid', 'some_policy_machine_uuid')
        expect(policy_machine_storage_adapter.element_in_machine?(src)).to be_truthy
      end

      it 'returns the instantiated policy element with persisted attribute set to true' do
        node = policy_machine_storage_adapter.send("add_#{pe_type}", 'some_uuid', 'some_policy_machine_uuid')
        expect(node.persisted).to be_truthy
      end
    end

    describe "find_all_of_type_#{pe_type}" do
      it 'returns empty array if nothing found' do
        expect(policy_machine_storage_adapter.send("find_all_of_type_#{pe_type}")).to be_empty
      end

      it 'returns array of found policy elements of given type if one is found' do
        node = policy_machine_storage_adapter.send("add_#{pe_type}", 'some_uuid', 'some_policy_machine_uuid')
        expect(policy_machine_storage_adapter.send("find_all_of_type_#{pe_type}")).to contain_exactly(node)
      end

      it 'returns array of found policy elements of given type if more than one is found' do
        node1 = policy_machine_storage_adapter.send("add_#{pe_type}", 'some_uuid1', 'some_policy_machine_uuid')
        node2 = policy_machine_storage_adapter.send("add_#{pe_type}", 'some_uuid2', 'some_policy_machine_uuid')
        expect(policy_machine_storage_adapter.send("find_all_of_type_#{pe_type}")).to contain_exactly(node1, node2)
      end

      context 'inclusions' do
        before do
          policy_machine_storage_adapter.send("add_#{pe_type}", 'some_uuid1', 'some_policy_machine_uuid', tags: ['up', 'down'])
          policy_machine_storage_adapter.send("add_#{pe_type}", 'some_uuid2', 'some_policy_machine_uuid', tags: ['up', 'strange'])
        end

        xit 'requires an exact match on array attributes' do
          expect(policy_machine_storage_adapter.send("find_all_of_type_#{pe_type}", tags: ['down', 'up'])).to be_empty
          expect(policy_machine_storage_adapter.send("find_all_of_type_#{pe_type}", tags: ['up', 'down'])).to be_one
        end

        it 'allows querying by checking whether a value is included in an array' do
          expect(policy_machine_storage_adapter.send("find_all_of_type_#{pe_type}", tags: {include: 'down'})).to be_one
        end

        it 'allows querying by checking whether multiple values are all included in an array' do
          expect(policy_machine_storage_adapter.send("find_all_of_type_#{pe_type}", tags: {include: ['down','up']})).to be_one
        end

        it 'performs substring matching' do
          expect(policy_machine_storage_adapter.send("find_all_of_type_#{pe_type}", unique_identifier: {include: '1'})).to be_one
        end

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

        it 'finds without case sensitivity if the option is set to true' do
          expect(policy_machine_storage_adapter.find_all_of_type_object(name: 'ABCDE', ignore_case: true).first.unique_identifier).to eq('abcde_uuid')
          expect(policy_machine_storage_adapter.find_all_of_type_object(name: 'oBJECt1', ignore_case: true).first.unique_identifier).to eq('object1_uuid')
        end

        it 'finds without case sensitivity if passed an array containing the sort key' do
          expect(policy_machine_storage_adapter.find_all_of_type_object(name: 'ABCDE', ignore_case: [:name]).first.unique_identifier).to eq('abcde_uuid')
        end

        it 'finds with case sensitivity if passed an array not containing the sort key' do
          expect(policy_machine_storage_adapter.find_all_of_type_object(name: 'ABCDE', ignore_case: [:color])).to eq([])
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
        expect(policy_machine_storage_adapter.connected?(@src, @dst)).to be_truthy
      end

      it 'does not connect the nodes from destination to source' do
        policy_machine_storage_adapter.assign(@src, @dst)
        expect(policy_machine_storage_adapter.connected?(@dst, @src)).to be_falsey
      end

      it 'returns true' do
        expect(policy_machine_storage_adapter.assign(@src, @dst)).to be_truthy
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
        expect(policy_machine_storage_adapter.connected?(@src, @dst)).to be_truthy
      end

      it 'returns false if source and destination nodes are not connected' do
        expect(policy_machine_storage_adapter.connected?(@src, @internal2)).to be_falsey
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

  describe '#linked?' do
    let(:src) { policy_machine_storage_adapter.add_user(SecureRandom.uuid, SecureRandom.uuid) }
    let(:dst) { policy_machine_storage_adapter.add_user(SecureRandom.uuid, SecureRandom.uuid) }
    let(:foo) { policy_machine_storage_adapter.add_user(SecureRandom.uuid, SecureRandom.uuid) }
    let(:bar) { policy_machine_storage_adapter.add_user(SecureRandom.uuid, SecureRandom.uuid) }

    before do
      policy_machine_storage_adapter.link(src, foo)
      policy_machine_storage_adapter.link(foo, dst)
    end

    it 'returns true if source and destination nodes are cross connected' do
      expect(policy_machine_storage_adapter.linked?(src, dst)).to eq true
    end

    it 'returns false if source and destination nodes are not cross connected' do
      expect(policy_machine_storage_adapter.linked?(src, bar)).to eq false
    end

    it 'returns false if source and destination nodes are the same' do
      expect(policy_machine_storage_adapter.linked?(src, src)).to eq false
    end

    it 'raises if the source is not a policy element' do
      expect { policy_machine_storage_adapter.linked?('', dst) }.to raise_error(ArgumentError)
    end

    it 'raises if the destination is not a policy element' do
      expect { policy_machine_storage_adapter.linked?(src, '') }.to raise_error(ArgumentError)
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
        expect(policy_machine_storage_adapter.connected?(@src, @dst)).to be_falsey
      end

      it 'does not disconnect destination from source node if there is an assignment in that direction' do
        policy_machine_storage_adapter.assign(@dst, @src)
        policy_machine_storage_adapter.unassign(@src, @dst)
        expect(policy_machine_storage_adapter.connected?(@dst, @src)).to be_truthy
      end

      it 'returns true on successful disconnection' do
        expect(policy_machine_storage_adapter.unassign(@src, @dst)).to be_truthy
      end

      it "returns false on unsuccessful disconnection (if the nodes weren't connected in the first place')" do
        policy_machine_storage_adapter.unassign(@src, @dst)
        expect(policy_machine_storage_adapter.unassign(@src, @dst)).to be_falsey
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
      expect(policy_machine_storage_adapter.element_in_machine?(@pe)).to be_truthy
    end
  end

  describe '#add_association' do
    before do
      @ua = policy_machine_storage_adapter.add_user_attribute('some_ua', 'some_policy_machine_uuid1')
      @reader_writer = policy_machine_storage_adapter.add_operation_set('reader_writer', 'some_policy_machine_uuid1')
      @reader = policy_machine_storage_adapter.add_operation_set('reader', 'some_policy_machine_uuid1')
      @r = policy_machine_storage_adapter.add_operation('read', 'some_policy_machine_uuid1')
      @w = policy_machine_storage_adapter.add_operation('write', 'some_policy_machine_uuid1')
      @oa = policy_machine_storage_adapter.add_object_attribute('some_oa', 'some_policy_machine_uuid1')
    end

    it 'returns true' do
      policy_machine_storage_adapter.assign(@reader_writer, @r)
      policy_machine_storage_adapter.assign(@reader_writer, @w)
      expect(policy_machine_storage_adapter.add_association(@ua, @reader_writer, @oa, 'some_policy_machine_uuid1')).to be_truthy
    end

    it 'stores the association' do
      policy_machine_storage_adapter.assign(@reader_writer, @r)
      policy_machine_storage_adapter.assign(@reader_writer, @w)
      policy_machine_storage_adapter.add_association(@ua, @reader_writer, @oa, 'some_policy_machine_uuid1')
      assocs_with_r = policy_machine_storage_adapter.associations_with(@r)
      expect(assocs_with_r.size).to eq 1
      expect(assocs_with_r[0][0]).to eq @ua
      expect(assocs_with_r[0][1]).to eq @reader_writer
      expect(assocs_with_r[0][2]).to eq @oa

      assocs_with_w = policy_machine_storage_adapter.associations_with(@w)
      assocs_with_w.size == 1
      expect(assocs_with_w[0][0]).to eq @ua
      expect(assocs_with_r[0][1]).to eq @reader_writer
      expect(assocs_with_r[0][2]).to eq @oa
    end

    xit 'overwrites a previously stored association' do
      policy_machine_storage_adapter.assign(@reader_writer, @r)
      policy_machine_storage_adapter.assign(@reader_writer, @w)
      policy_machine_storage_adapter.assign(@reader, @r)
      policy_machine_storage_adapter.add_association(@ua, @reader_writer, @oa, 'some_policy_machine_uuid1')
      policy_machine_storage_adapter.add_association(@ua, @reader, @oa, 'some_policy_machine_uuid1')
      assocs_with_r = policy_machine_storage_adapter.associations_with(@r)
      assocs_with_r.size == 1
      expect(assocs_with_r[0][0]).to eq @ua
      expect(assocs_with_r[0][1].to_a).to contain_exactly(@r)
      expect(assocs_with_r[0][2]).to eq @oa

      expect(policy_machine_storage_adapter.associations_with(@w)).to be_empty
    end
  end

  describe '#associations_with' do
    before do
      @ua = policy_machine_storage_adapter.add_user_attribute('some_ua', 'some_policy_machine_uuid1')
      @ua2 = policy_machine_storage_adapter.add_user_attribute('some_other_ua', 'some_policy_machine_uuid1')
      @r = policy_machine_storage_adapter.add_operation('read', 'some_policy_machine_uuid1')
      @writer = policy_machine_storage_adapter.add_operation_set('writer', 'some_policy_machine_uuid1')
      @writer_editor = policy_machine_storage_adapter.add_operation_set('writer_editor', 'some_policy_machine_uuid1')
      @w = policy_machine_storage_adapter.add_operation('write', 'some_policy_machine_uuid1')
      @e = policy_machine_storage_adapter.add_operation('execute', 'some_policy_machine_uuid1')
      @oa = policy_machine_storage_adapter.add_object_attribute('some_oa', 'some_policy_machine_uuid1')
    end

    it 'returns empty array when given operation has no associated associations' do
      expect(policy_machine_storage_adapter.associations_with(@r)).to be_empty
    end

    it 'returns structured array when given operation has associated associations' do
      policy_machine_storage_adapter.assign(@writer, @w)
      policy_machine_storage_adapter.assign(@writer_editor, @w)
      policy_machine_storage_adapter.assign(@writer_editor, @e)
      policy_machine_storage_adapter.add_association(@ua, @writer, @oa, 'some_policy_machine_uuid1')
      policy_machine_storage_adapter.add_association(@ua2, @writer_editor, @oa, 'some_policy_machine_uuid1')
      assocs_with_w = policy_machine_storage_adapter.associations_with(@w)

      assocs_with_w.size == 2
      expect(assocs_with_w[0][0]).to eq @ua
      expect(assocs_with_w[0][1]).to eq @writer
      expect(assocs_with_w[0][2]).to eq @oa
      expect(assocs_with_w[1][0]).to eq @ua2
      expect(assocs_with_w[1][1]).to eq @writer_editor
      expect(assocs_with_w[1][2]).to eq @oa
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
      expect(policy_machine_storage_adapter.policy_classes_for_object_attribute(@oa)).to be_empty
    end

    it 'returns array of policy class(es) if object is in policy class(es)' do
      policy_machine_storage_adapter.assign(@oa, @pc1)
      policy_machine_storage_adapter.assign(@oa, @pc3)
      expect(policy_machine_storage_adapter.policy_classes_for_object_attribute(@oa)).to contain_exactly(@pc1, @pc3)
    end

    it 'handles non unique associations' do
      policy_machine_storage_adapter.assign(@oa, @pc1)
      expect { policy_machine_storage_adapter.assign(@oa, @pc1) }.to_not raise_error
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
      expect(policy_machine_storage_adapter.policy_classes_for_object_attribute(@oa)).to contain_exactly(@pc1)
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
      expect(policy_machine_storage_adapter.find_all_of_type_policy_class).to contain_exactly(@pc1)
      expect(policy_machine_storage_adapter.policy_classes_for_object_attribute(@oa)).to contain_exactly(@pc1)
    end
  end

end
