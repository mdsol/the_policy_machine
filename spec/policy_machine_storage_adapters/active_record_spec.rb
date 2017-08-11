require 'spec_helper'
require 'policy_machine_storage_adapters/active_record'
require 'database_cleaner'

DatabaseCleaner.strategy = :truncation

describe 'ActiveRecord' do
  before(:all) do
    ENV["RAILS_ENV"] = "test"
    begin
      require_relative '../../test/testapp/config/environment.rb'
    rescue LoadError
      raise "Failed to locate test/testapp/config/environment.rb. Execute 'rake pm:test:prepare' to generate test/testapp."
    end
    Rails.backtrace_cleaner.remove_silencers!
  end

  before(:each) do
    Rails.cache.clear
    DatabaseCleaner.clean
  end

  policy_element_types = ::PolicyMachine::POLICY_ELEMENT_TYPES

  describe PolicyMachineStorageAdapter::ActiveRecord do
    let(:policy_machine_storage_adapter) { described_class.new }

    context 'public methods' do
      policy_element_types = ::PolicyMachine::POLICY_ELEMENT_TYPES
      required_public_methods = []
      policy_element_types.each do |pe_type|
        required_public_methods << "add_#{pe_type}"
        required_public_methods << "find_all_of_type_#{pe_type}"
      end
      required_public_methods += %w(assign connected? unassign delete update element_in_machine? add_association associations_with policy_classes_for_object_attribute transaction)

      required_public_methods.each do |req_public_method|
        it "responds to #{req_public_method}" do
          expect(policy_machine_storage_adapter).to respond_to(req_public_method)
        end
      end
    end

    describe 'instantiation' do
      it 'has a default name' do
        expect(PolicyMachine.new.name.length).to_not eq 0
      end

      it 'can be named' do
        ['name', :name].each do |key|
          expect(PolicyMachine.new(key => 'my name').name).to eq 'my name'
        end
      end

      it 'sets the uuid if not specified' do
        expect(PolicyMachine.new.uuid.length).to_not eq 0
      end

      it 'allows uuid to be specified' do
        ['uuid', :uuid].each do |key|
          expect(PolicyMachine.new(key => 'my uuid').uuid).to eq 'my uuid'
        end
      end

      it 'raises when uuid is blank' do
        ['', '   '].each do |blank_value|
          expect{ PolicyMachine.new(:uuid => blank_value) }.to raise_error(ArgumentError, 'uuid cannot be blank')
        end
      end

      it 'defaults to in-memory storage adapter' do
        expect(PolicyMachine.new.policy_machine_storage_adapter).to be_a(::PolicyMachineStorageAdapter::InMemory)
      end

      it 'allows user to set storage adapter' do
        ['storage_adapter', :storage_adapter].each do |key|
          storage_adapter = PolicyMachine.new(key => ::PolicyMachineStorageAdapter::Neography).policy_machine_storage_adapter
          expect(storage_adapter).to be_a(::PolicyMachineStorageAdapter::Neography)
        end
      end
    end

    describe 'Assignments' do
      allowed_assignments = [
        ['object', 'object'],
        ['object', 'object_attribute'],
        ['object_attribute', 'object_attribute'],
        ['object_attribute', 'object'],
        ['user', 'user_attribute'],
        ['user_attribute', 'user_attribute'],
        ['user_attribute', 'policy_class'],
        ['object_attribute', 'policy_class'],
        ['operation_set', 'operation_set'],
        ['operation_set', 'operation']
      ]

      # Add an assignment e.g. o -> oa or oa -> oa or u -> ua or ua -> ua.
      describe 'Adding' do
        allowed_assignments.each do |allowed_assignment|
          it "allows a #{allowed_assignment[0]} to be assigned a #{allowed_assignment[1]} (returns true)" do
            pe0 = policy_machine.send("create_#{allowed_assignment[0]}", SecureRandom.uuid)
            pe1 = policy_machine.send("create_#{allowed_assignment[1]}", SecureRandom.uuid)

            expect(policy_machine.add_assignment(pe0, pe1)).to be_truthy
          end
        end

        disallowed_assignments = policy_element_types.product(policy_element_types) - allowed_assignments
        disallowed_assignments.each do |disallowed_assignment|
          it "does not allow a #{disallowed_assignment[0]} to be assigned a #{disallowed_assignment[1]} (raises)" do
            pe0 = policy_machine.send("create_#{disallowed_assignment[0]}", SecureRandom.uuid)
            pe1 = policy_machine.send("create_#{disallowed_assignment[1]}", SecureRandom.uuid)

            expect{ policy_machine.add_assignment(pe0, pe1) }.to raise_error(ArgumentError)
          end
        end

        it 'raises when first argument is not a policy element' do
          pe = policy_machine.create_user_attribute(SecureRandom.uuid)
          expect{ policy_machine.add_assignment(1, pe) }
            .to raise_error(ArgumentError, "arg must each be a kind of PolicyElement; got #{SmallNumber} instead")
        end

        it 'raises when first argument is not in policy machine' do
          pm2 = PolicyMachine.new
          pe0 = pm2.create_user_attribute(SecureRandom.uuid)
          pe1 = policy_machine.create_user_attribute(SecureRandom.uuid)
          expect{ policy_machine.add_assignment(pe0, pe1) }
            .to raise_error(ArgumentError, "#{pe0.unique_identifier} is not in policy machine with uuid #{policy_machine.uuid}")
        end

        it 'raises when second argument is not a policy element' do
          pe = policy_machine.create_user_attribute(SecureRandom.uuid)
          expect{ policy_machine.add_assignment(pe, "hello") }
            .to raise_error(ArgumentError, "arg must each be a kind of PolicyElement; got String instead")
        end

        it 'raises when second argument is not in policy machine' do
          pm2 = PolicyMachine.new
          pe0 = policy_machine.create_user_attribute(SecureRandom.uuid)
          pe1 = pm2.create_user_attribute(SecureRandom.uuid)
          expect{ policy_machine.add_assignment(pe0, pe1) }
            .to raise_error(ArgumentError, "#{pe1.unique_identifier} is not in policy machine with uuid #{policy_machine.uuid}")
        end
      end

      describe 'Removing' do
        before do
          @pe0 = policy_machine.create_user(SecureRandom.uuid)
          @pe1 = policy_machine.create_user_attribute(SecureRandom.uuid)
        end

        it 'removes an existing assignment (returns true)' do
          policy_machine.add_assignment(@pe0, @pe1)
          expect(policy_machine.remove_assignment(@pe0, @pe1)).to be_truthy
        end

        it 'does not remove a non-existant assignment (returns false)' do
          expect(policy_machine.remove_assignment(@pe0, @pe1)).to be_falsey
        end

        it 'raises when first argument is not a policy element' do
          expect{ policy_machine.add_assignment(1, @pe1) }
            .to raise_error(ArgumentError, "arg must each be a kind of PolicyElement; got #{SmallNumber} instead")
        end

        it 'raises when first argument is not in policy machine' do
          pm2 = PolicyMachine.new
          pe0 = pm2.create_user_attribute(SecureRandom.uuid)
          pe1 = policy_machine.create_user_attribute(SecureRandom.uuid)
          expect{ policy_machine.remove_assignment(pe0, pe1) }
            .to raise_error(ArgumentError, "#{pe0.unique_identifier} is not in policy machine with uuid #{policy_machine.uuid}")
        end

        it 'raises when second argument is not a policy element' do
          expect{ policy_machine.add_assignment(@pe0, "hello") }
            .to raise_error(ArgumentError, "arg must each be a kind of PolicyElement; got String instead")
        end

        it 'raises when second argument is not in policy machine' do
          pm2 = PolicyMachine.new
          pe0 = policy_machine.create_user_attribute(SecureRandom.uuid)
          pe1 = pm2.create_user_attribute(SecureRandom.uuid)
          expect{ policy_machine.remove_assignment(pe0, pe1) }
            .to raise_error(ArgumentError, "#{pe1.unique_identifier} is not in policy machine with uuid #{policy_machine.uuid}")
        end
      end
    end

    describe 'LogicalLinks' do
      let(:pm1) { PolicyMachine.new(name: 'PM 1', storage_adapter: policy_machine.policy_machine_storage_adapter.class) }
      let(:pm2) { PolicyMachine.new(name: 'PM 2', storage_adapter: policy_machine.policy_machine_storage_adapter.class) }
      let(:pm3) { PolicyMachine.new(name: 'PM 3', storage_adapter: policy_machine.policy_machine_storage_adapter.class) }
      let(:pe1) { pm1.create_user_attribute(SecureRandom.uuid) }
      let(:pe2) { pm2.create_user_attribute(SecureRandom.uuid) }
      let(:pe3) { pm1.create_user_attribute(SecureRandom.uuid) }

      # All possible combinations of two policy machine types are allowed to be linked.
      allowed_links = policy_element_types.product(policy_element_types)

      describe 'Adding a link' do
        allowed_links.each do |aca|
          it "allows a #{aca[0]} to be assigned a #{aca[1]}" do
            policy_element1 = pm1.send("create_#{aca[0]}", SecureRandom.uuid)
            policy_element2 = pm2.send("create_#{aca[1]}", SecureRandom.uuid)

            expect { pm1.add_link(policy_element1, policy_element2) }
              .to change { policy_element1.linked?(policy_element2) }.from(false).to(true)
          end

          it "allows a #{aca[0]} to be assigned a #{aca[1]} using an unrelated policy machine" do
            policy_element1 = pm1.send("create_#{aca[0]}", SecureRandom.uuid)
            policy_element2 = pm2.send("create_#{aca[1]}", SecureRandom.uuid)

            expect { pm3.add_link(policy_element1, policy_element2) }
              .to change { policy_element1.linked?(policy_element2) }.from(false).to(true)
          end
        end

        it 'raises when the first argument is not a policy element' do
          err_msg = "args must each be a kind of PolicyElement; got a #{SmallNumber} and PM::UserAttribute instead"
          expect{ pm1.add_link(1, pe1) }.to raise_error(ArgumentError, err_msg)
        end

        it 'raises when the second argument is not a policy element' do
          err_msg = "args must each be a kind of PolicyElement; got a PM::UserAttribute and #{SmallNumber} instead"
          expect{ pm1.add_link(pe1, 1) }.to raise_error(ArgumentError, err_msg)
        end

        it 'raises when the arguments are in the same policy machine' do
          err_msg = "#{pe1.unique_identifier} and #{pe3.unique_identifier} are in the same policy machine"
          expect{ pm1.add_link(pe1, pe3) }.to raise_error(ArgumentError, err_msg)
        end
      end

      describe 'Removing a link' do
        it 'removes an existing link' do
          pm1.add_link(pe1, pe2)
          expect { pm1.remove_link(pe1, pe2) }
            .to change { pe1.linked?(pe2) }.from(true).to(false)
        end

        it 'does not remove a non-existant link' do
          expect { pm1.remove_link(pe1, pe2) }
            .to_not change { pe1.linked?(pe2) }
          expect(pe1.linked?(pe2)).to eq false
        end

        it 'raises when first argument is not a policy element' do
          err_msg = "args must each be a kind of PolicyElement; got a #{SmallNumber} and PM::UserAttribute instead"
          expect{ pm1.add_link(1, pe1) }.to raise_error(ArgumentError, err_msg)
        end

        it 'raises when the second argument is not a policy element' do
          err_msg = 'args must each be a kind of PolicyElement; got a PM::UserAttribute and String instead'
          expect{ pm1.add_link(pe1, 'pe2') }.to raise_error(ArgumentError, err_msg)
        end

        it 'raises when the first argument is in the same policy machine' do
          err_msg = "#{pe1.unique_identifier} and #{pe3.unique_identifier} are in the same policy machine"
          expect{ pm1.remove_link(pe1, pe3) }.to raise_error(ArgumentError, err_msg)
        end
      end

      describe 'bulk_persist' do
        describe 'Adding a link' do
          allowed_links.each do |aca|
            it "allows a #{aca[0]} to be assigned a #{aca[1]}" do
              policy_element1 = pm1.send("create_#{aca[0]}", SecureRandom.uuid)
              policy_element2 = pm2.send("create_#{aca[1]}", SecureRandom.uuid)

              expect do
                pm1.bulk_persist { pm1.add_link(policy_element1, policy_element2) }
              end.to change { policy_element1.linked?(policy_element2) }.from(false).to(true)
            end

            it "allows a #{aca[0]} to be assigned a #{aca[1]} using an unrelated policy machine" do
              policy_element1 = pm1.send("create_#{aca[0]}", SecureRandom.uuid)
              policy_element2 = pm2.send("create_#{aca[1]}", SecureRandom.uuid)

              expect do
                pm1.bulk_persist { pm3.add_link(policy_element1, policy_element2) }
              end.to change { policy_element1.linked?(policy_element2) }.from(false).to(true)
            end
          end

          it 'adds multiple links at once' do
            expect(pe1.linked?(pe2)).to eq false
            expect(pe2.linked?(pe3)).to eq false

            pm1.bulk_persist do
              pm1.add_link(pe1, pe2)
              pm1.add_link(pe2, pe3)
            end

            expect(pe1.linked?(pe2)).to eq true
            expect(pe2.linked?(pe3)).to eq true
          end

          it 'raises when the first argument is not a policy element' do
            err_msg = "args must each be a kind of PolicyElement; got a #{SmallNumber} and PM::UserAttribute instead"
            expect{ pm1.bulk_persist { pm1.add_link(1, pe1) } }.to raise_error(ArgumentError, err_msg)
          end

          it 'raises when the second argument is not a policy element' do
            err_msg = "args must each be a kind of PolicyElement; got a PM::UserAttribute and #{SmallNumber} instead"
            expect{ pm1.bulk_persist { pm1.add_link(pe1, 1) } }.to raise_error(ArgumentError, err_msg)
          end

          it 'raises when the arguments are in the same policy machine' do
            err_msg = "#{pe1.unique_identifier} and #{pe3.unique_identifier} are in the same policy machine"
            expect{ pm1.bulk_persist { pm1.add_link(pe1, pe3) } }.to raise_error(ArgumentError, err_msg)
          end
        end

        describe 'Removing a link' do
          it 'removes an existing link' do
            pm1.add_link(pe1, pe2)
            expect { pm1.bulk_persist { pm1.remove_link(pe1, pe2) } }
              .to change { pe1.linked?(pe2) }.from(true).to(false)
          end

          it 'removes multiple links at once' do
            pm1.add_link(pe1, pe2)
            pm1.add_link(pe2, pe3)

            expect(pe1.linked?(pe2)).to eq true
            expect(pe2.linked?(pe3)).to eq true

            pm1.bulk_persist do
              pm1.remove_link(pe1, pe2)
              pm1.remove_link(pe2, pe3)
            end

            expect(pe1.linked?(pe2)).to eq false
            expect(pe2.linked?(pe3)).to eq false
          end

          it 'does not remove a non-existant link' do
            expect { pm1.bulk_persist { pm1.remove_link(pe1, pe2) } }
              .to_not change { pe1.linked?(pe2) }
            expect(pe1.linked?(pe2)).to eq false
          end

          it 'raises when first argument is not a policy element' do
            err_msg = "args must each be a kind of PolicyElement; got a #{SmallNumber} and PM::UserAttribute instead"
            expect{ pm1.bulk_persist { pm1.add_link(1, pe1) } }.to raise_error(ArgumentError, err_msg)
          end

          it 'raises when the second argument is not a policy element' do
            err_msg = 'args must each be a kind of PolicyElement; got a PM::UserAttribute and String instead'
            expect{ pm1.bulk_persist { pm1.add_link(pe1, 'pe2') } }.to raise_error(ArgumentError, err_msg)
          end

          it 'raises when the first argument is in the same policy machine' do
            err_msg = "#{pe1.unique_identifier} and #{pe3.unique_identifier} are in the same policy machine"
            expect{ pm1.bulk_persist { pm1.remove_link(pe1, pe3) } }.to raise_error(ArgumentError, err_msg)
          end
        end
      end
    end

    describe 'Associations' do
      describe 'Adding' do
        before do
          @object_attribute = policy_machine.create_object_attribute('OA name')
          @operation_set = policy_machine.create_operation_set('reader_writer')
          @operation1 = policy_machine.create_operation('read')
          @operation2 = policy_machine.create_operation('write')
          @set_of_operation_objects = Set.new [@operation1, @operation2]
          @user_attribute = policy_machine.create_user_attribute('UA name')
        end

        it 'raises when first argument is not a PolicyElement' do
          expect{ policy_machine.add_association("234", @set_of_operation_objects, @operation_set, @object_attribute) }
            .to raise_error(ArgumentError, "arg must each be a kind of PolicyElement; got String instead")
        end

        it 'raises when first argument is not in policy machine' do
          pm2 = PolicyMachine.new
          ua = pm2.create_user_attribute(SecureRandom.uuid)
          expect{ policy_machine.add_association(ua, @set_of_operation_objects, @operation_set, @object_attribute) }
            .to raise_error(ArgumentError, "#{ua.unique_identifier} is not in policy machine with uuid #{policy_machine.uuid}")
        end

        it 'raises when third argument is not a PolicyElement' do
          expect{ policy_machine.add_association(@user_attribute, @set_of_operation_objects, @operation_set, 3) }
            .to raise_error(ArgumentError, "arg must each be a kind of PolicyElement; got #{SmallNumber} instead")
        end

        it 'raises when third argument is not in policy machine' do
          pm2 = PolicyMachine.new
          oa = pm2.create_object_attribute(SecureRandom.uuid)
          expect{ policy_machine.add_association(@user_attribute, @set_of_operation_objects, @operation_set, oa) }
            .to raise_error(ArgumentError, "#{oa.unique_identifier} is not in policy machine with uuid #{policy_machine.uuid}")
        end

        it 'allows an association to be made between an existing user_attribute, operation set and object attribute (returns true)' do
          expect(policy_machine.add_association(@user_attribute, @set_of_operation_objects, @operation_set, @object_attribute)).to be_truthy
        end

        it 'handles non-unique operation sets' do
          @set_of_operation_objects << @operation1.dup
          expect(policy_machine.add_association(@user_attribute, @set_of_operation_objects, @operation_set, @object_attribute)).to be_truthy
        end

        xit 'overwrites old associations between the same attributes' do
          first_op_set = policy_machine.create_operation_set('first_op_set')
          second_op_set = policy_machine.create_operation_set('second_op_set')
          policy_machine.add_association(@user_attribute, Set.new([@operation1]), first_op_set, @object_attribute)

          expect{policy_machine.add_association(@user_attribute, Set.new([@operation2]), second_op_set, @object_attribute)}
            .to change{ policy_machine.scoped_privileges(@user_attribute, @object_attribute) }
            .from( [[@user_attribute, @operation1, @object_attribute]] )
            .to(   [[@user_attribute, @operation2, @object_attribute]] )
        end
      end
    end

    describe 'All methods for policy elements' do
      PolicyMachine::POLICY_ELEMENT_TYPES.each do |pe_type|
        it "returns an array of all #{pe_type.to_s.pluralize}" do
          pe = policy_machine.send("create_#{pe_type}", 'some name')
          expect(policy_machine.send(pe_type.to_s.pluralize)).to eq([pe])
        end

        it "scopes by policy machine when finding an array of #{pe_type.to_s.pluralize}" do
          pe = policy_machine.send("create_#{pe_type}", 'some name')
          other_pm = PolicyMachine.new
          pe_in_other_machine = other_pm.send("create_#{pe_type}", 'some name')
          expect(policy_machine.send(pe_type.to_s.pluralize)).to eq([pe])
        end
      end
    end

    describe 'Operations' do
      it 'does not allow an operation to start with a ~' do
        expect{policy_machine.create_operation('~apple')}.to raise_error(ArgumentError)
        expect{policy_machine.create_operation('apple~')}.not_to raise_error
      end

      it 'can derive a prohibition from an operation and vice versa' do
        @op = policy_machine.create_operation('fly')
        expect(@op.prohibition).to be_prohibition
        expect(@op.prohibition.operation).to eq('fly')
      end

      it 'raises if trying to negate a non-operation' do
        expect{PM::Prohibition.on(3)}.to raise_error(ArgumentError)
      end

      it 'can negate operations expressed as strings' do
        expect(PM::Prohibition.on('fly')).to be_a String
      end

      it 'can negate operations expressed as symbols' do
        expect(PM::Prohibition.on(:fly)).to be_a Symbol
      end

      it 'can negate operations expressed as PM::Operations' do
        expect(PM::Prohibition.on(policy_machine.create_operation('fly'))).to be_a PM::Operation
      end
    end

    describe 'User Attributes' do
      describe '#extra_attributes' do
        it 'accepts and persists arbitrary extra attributes' do
          @ua = policy_machine.create_user_attribute('ua1', foo: 'bar')
          expect(@ua.foo).to eq 'bar'
          expect(policy_machine.user_attributes.last.foo).to eq 'bar'
        end
      end

      describe '#delete' do
        it 'successfully deletes itself' do
          @ua = policy_machine.create_user_attribute('ua1')
          @ua.delete
          expect(policy_machine.user_attributes).to_not include(@ua)
        end
      end
    end

    describe 'Users' do
      describe '#extra_attributes' do
        it 'accepts and persists arbitrary extra attributes' do
          @u = policy_machine.create_user('u1', foo: 'bar')
          expect(@u.foo).to eq 'bar'
          expect(policy_machine.users.last.foo).to eq 'bar'
        end

        it 'updates persisted extra attributes' do
          @u = policy_machine.create_user('u1', foo: 'bar')
          @u.update(foo: 'baz')
          expect(@u.foo).to eq 'baz'
          expect(policy_machine.users.last.foo).to eq 'baz'
        end

        it 'updates persisted extra attributes with new keys' do
          @u = policy_machine.create_user('u1', foo: 'bar')
          @u.update(foo: 'baz', bla: 'bar')
          expect(@u.foo).to eq 'baz'
          expect(policy_machine.users.last.foo).to eq 'baz'
        end

        it 'does not remove old attributes when adding new ones' do
          @u = policy_machine.create_user('u1', foo: 'bar')
          @u.update(deleted: true)
          expect(@u.foo).to eq 'bar'
          expect(policy_machine.users.last.foo).to eq 'bar'
        end

        it 'allows searching on any extra attribute keys' do
          policy_machine.create_user('u1', foo: 'bar')
          policy_machine.create_user('u2', foo: nil, attitude: 'sassy')
          silence_warnings do
            expect(policy_machine.users(foo: 'bar')).to be_one
            expect(policy_machine.users(foo: nil)).to be_one
            expect(policy_machine.users(foo: 'baz')).to be_none
            expect(policy_machine.users(foo: 'bar', attitude: 'sassy')).to be_none
          end
        end
      end
    end

    describe '#is_privilege?' do
      before do
        # Define policy elements
        @u1 = policy_machine.create_user('u1')
        @o1 = policy_machine.create_object('o1')
        @o2 = policy_machine.create_object('o2')
        @group1 = policy_machine.create_user_attribute('Group1')
        @project1 = policy_machine.create_object_attribute('Project1')
        @writer = policy_machine.create_operation_set('writer')
        @w = policy_machine.create_operation('write')

        # Assignments
        policy_machine.add_assignment(@u1, @group1)
        policy_machine.add_assignment(@o1, @project1)

        # Associations
        policy_machine.add_association(@group1, Set.new([@w]), @writer, @project1)

        # Cross Assignments included to show that privilege derivations are unaffected
        pm2 = PolicyMachine.new(name: 'Another PM', storage_adapter: policy_machine.policy_machine_storage_adapter.class)
        @another_u1 = pm2.create_user('Another u1')
        @another_o1 = pm2.create_object('Another o1')
        @another_o2 = pm2.create_object('Another o2')
        @another_group1 = pm2.create_user_attribute('Another Group1')
        @another_project1 = pm2.create_object_attribute('Another Project1')
        @another_w = pm2.create_operation('Another write')

        pm2.add_link(@u1, @another_u1)
        pm2.add_link(@o1, @another_o1)
        pm2.add_link(@o2, @another_o2)
        pm2.add_link(@group1, @another_group1)
        pm2.add_link(@project1, @another_project1)
        pm2.add_link(@w, @another_w)

        pm2.add_link(@u1, @another_group1)
        pm2.add_link(@o1, @another_project1)
        pm2.add_link(@project1, @another_w)

        pm2.add_link(@another_u1, @group1)
        pm2.add_link(@another_o1, @project1)
        pm2.add_link(@another_project1, @w)
      end

      it 'raises when the first argument is not a user or user_attribute' do
        expect{ policy_machine.is_privilege?(@o1, @w, @o1)}.
          to raise_error(ArgumentError, "user_attribute_pe must be a User or UserAttribute.")
      end

      it 'raises when the second argument is not an operation, symbol, or string' do
        expect{ policy_machine.is_privilege?(@u1, @u1, @o1)}.
          to raise_error(ArgumentError, "operation must be an Operation, Symbol, or String.")
      end

      it 'raises when the third argument is not an object or object_attribute' do
        expect{ policy_machine.is_privilege?(@u1, @w, @u1)}.
          to raise_error(ArgumentError, "object_or_attribute must either be an Object or ObjectAttribute.")
      end

      it 'returns true if privilege can be inferred from user, operation and object' do
        expect(policy_machine.is_privilege?(@u1, @w, @o1)).to be_truthy
      end

      it 'returns true if privilege can be inferred from user_attribute, operation and object' do
        expect(policy_machine.is_privilege?(@group1, @w, @o1)).to be_truthy
      end

      it 'returns true if privilege can be inferred from user, operation and object_attribute' do
        expect(policy_machine.is_privilege?(@u1, @w, @project1)).to be_truthy
      end

      it 'returns false if privilege cannot be inferred from arguments' do
        expect(policy_machine.is_privilege?(@u1, @w, @o2)).to be_falsey
      end

      it 'accepts the unique identifier for an operation in place of the operation' do
        expect(policy_machine.is_privilege?(@u1, @w.unique_identifier, @o1)).to be_truthy
      end

      it 'accepts the unique identifier in symbol form for an operation in place of the operation' do
        expect(policy_machine.is_privilege?(@u1, @w.unique_identifier.to_sym, @o1)).to be_truthy
      end

      it 'returns false on string input when the operation exists but the privilege does not' do
        expect(policy_machine.is_privilege?(@u1, @w.unique_identifier, @o2)).to be_falsey
      end

      it 'returns false on string input when the operation does not exist' do
        expect(policy_machine.is_privilege?(@u1, 'non-existent-operation', @o2)).to be_falsey
      end

      it 'does not infer privileges from deleted attributes' do
        @group1.delete
        expect(policy_machine.is_privilege?(@u1, @w, @o1)).to be_falsey
      end

      describe 'options' do
        describe 'associations' do
          it 'raises unless options[:associations] is an Array' do
            expect{ policy_machine.is_privilege?(@u1, @w, @o2, :associations => 4) }.
              to raise_error(ArgumentError, "expected options[:associations] to be an Array; got #{SmallNumber}")
          end

          it 'raises if options[:associations] is an empty array' do
            expect{ policy_machine.is_privilege?(@u1, @w, @o2, :associations => []) }.
              to raise_error(ArgumentError, "options[:associations] cannot be empty")
          end

          it 'raises unless every element of options[:associations] is a PM::Association' do
            expect{ policy_machine.is_privilege?(@u1, @w, @o2, :associations => [4]) }.
              to raise_error(ArgumentError, "expected each element of options[:associations] to be a PM::Association")
          end

          it 'raises if no element of options[:associations] contains the given operation' do
            executer = policy_machine.create_operation_set('executer')
            e = policy_machine.create_operation('execute')
            policy_machine.add_association(@group1, Set.new([e]), executer, @project1)
            expect(policy_machine.is_privilege?(@u1, @w, @o2, :associations => e.associations)).to be_falsey
          end

          it 'accepts associations in options[:associations]' do
            expect(policy_machine.is_privilege?(@u1, @w, @o1, :associations => @w.associations)).to be_truthy
          end

          it "accepts associations in options['associations']" do
            expect(policy_machine.is_privilege?(@u1, @w, @o1, 'associations' => @w.associations)).to be_truthy
          end

          it 'returns true when given association is part of the granting of a given privilege' do
            expect(policy_machine.is_privilege?(@u1, @w, @o1, 'associations' => @w.associations)).to be_truthy
          end

          it 'returns false when given association is not part of the granting of a given privilege' do
            group2 = policy_machine.create_user_attribute('Group2')

            policy_machine.add_association(group2, Set.new([@w]), @writer, @project1)
            expect(policy_machine.is_privilege?(@u1, @w, @o1, 'associations' => [@w.associations.last])).to be_falsey
          end
        end

        describe 'in_user_attribute' do
          it 'raises unless options[:in_user_attribute] is a PM::UserAttribute' do
            expect{ policy_machine.is_privilege?(@u1, @w, @o2, :in_user_attribute => 4) }.
              to raise_error(ArgumentError, "expected options[:in_user_attribute] to be a PM::UserAttribute; got #{SmallNumber}")
          end

          it 'accepts in_user_attribute in options[:in_user_attribute]' do
            expect(policy_machine.is_privilege?(@u1, @w, @o1, :in_user_attribute => @group1)).to be_truthy
          end

          it "accepts in_user_attribute in options['in_user_attribute']" do
            expect(policy_machine.is_privilege?(@group1, @w, @o1, 'in_user_attribute' => @group1)).to be_truthy
          end

          it 'returns false if given user is not in given in_user_attribute' do
            group2 = policy_machine.create_user_attribute('Group2')
            expect(policy_machine.is_privilege?(@u1, @w, @o1, 'in_user_attribute' => group2)).to be_falsey
          end
        end

        describe 'in_object_attribute' do
          it 'raises unless options[:in_object_attribute] is a PM::ObjectAttribute' do
            expect{ policy_machine.is_privilege?(@u1, @w, @o2, :in_object_attribute => 4) }.
              to raise_error(ArgumentError, "expected options[:in_object_attribute] to be a PM::ObjectAttribute; got #{SmallNumber}")
          end

          it 'accepts in_object_attribute in options[:in_object_attribute]' do
            expect(policy_machine.is_privilege?(@u1, @w, @o1, :in_object_attribute => @project1)).to be_truthy
          end

          it "accepts in_object_attribute in options['in_object_attribute']" do
            expect(policy_machine.is_privilege?(@u1, @w, @project1, 'in_object_attribute' => @project1)).to be_truthy
          end

          it 'returns false if given user is not in given in_object_attribute' do
            project2 = policy_machine.create_object_attribute('Project2')
            expect(policy_machine.is_privilege?(@u1, @w, @o1, 'in_object_attribute' => project2)).to be_falsey
          end

          it 'accepts both in_user_attribute and in_object_attribute' do
            project2 = policy_machine.create_object_attribute('Project2')
            expect(policy_machine.is_privilege?(@u1, @w, @o1, 'in_user_attribute' => @group1, 'in_object_attribute' => project2))
              .to be_falsey
          end
        end
      end
    end

    describe '#list_user_attributes' do
      before do
        # Define policy elements
        @u1 = policy_machine.create_user('u1')
        @u2 = policy_machine.create_user('u2')
        @group1 = policy_machine.create_user_attribute('Group1')
        @group2 = policy_machine.create_user_attribute('Group2')
        @subgroup1a = policy_machine.create_user_attribute('Subgroup1a')

        # Assignments
        policy_machine.add_assignment(@u1, @subgroup1a)
        policy_machine.add_assignment(@subgroup1a, @group1)
        policy_machine.add_assignment(@u2, @group2)
      end

      it 'lists the user attributes for a user' do
        expect(policy_machine.list_user_attributes(@u2)).to contain_exactly(@group2)
      end

      it 'searches multiple hops deep' do
        expect(policy_machine.list_user_attributes(@u1)).to contain_exactly(@group1, @subgroup1a)
      end

      it 'raises an argument error when passed anything other than a user' do
        expect {policy_machine.list_user_attributes(@group1)}.to raise_error ArgumentError, /Expected a PM::User/
      end
    end

    describe '#transaction' do
      it 'executes the block' do
        if_implements(policy_machine.policy_machine_storage_adapter, :transaction){}
        policy_machine.transaction do
          @oa = policy_machine.create_object_attribute('some_oa')
        end
        expect(policy_machine.object_attributes).to contain_exactly(@oa)
      end

      it 'rolls back the block on error' do
        if_implements(policy_machine.policy_machine_storage_adapter, :transaction){}
        @oa1 = policy_machine.create_object_attribute('some_oa')
        expect do
          policy_machine.transaction do
            @oa2 = policy_machine.create_object_attribute('some_other_oa')
            policy_machine.add_assignment(@oa2, :invalid_policy_class)
          end
        end.to raise_error(ArgumentError)
        expect(policy_machine.object_attributes).to contain_exactly(@oa1)
      end
    end

    describe '#privileges' do

      [nil, ' in bulk create mode'].each do |bulk_create_mode|

        # This PM is taken from the policy machine spec, Figure 4. (pg. 19)
        #TODO better cleaner stronger faster tests needed
        describe "Simple Example:  Figure 4. (pg. 19)#{bulk_create_mode}" do
          before do
            #Elements for update tests
            default_args = {foo: nil, color: nil}
            @u4 = policy_machine.create_user('u4', default_args)
            @o4 = policy_machine.create_object('o4', default_args)
            @preexisting_group = policy_machine.create_user_attribute('preexisting_group', default_args)
            @preexisting_project = policy_machine.create_object_attribute('preexisting_project', default_args)
            @preexisting_policy_class = policy_machine.create_policy_class('preexisting_policy_class', default_args)
            @editor = policy_machine.create_operation_set('editor')
            @e = policy_machine.create_operation('edit')

            # Elements for delete tests
            @u5 = policy_machine.create_user('u5')
            @u6 = policy_machine.create_user('u6')
            @o5 = policy_machine.create_object('o5')
            @o6 = policy_machine.create_object('o6')
            @group3 = policy_machine.create_user_attribute('Group3')
            @project3 = policy_machine.create_object_attribute('Project3')

            # Assignments for delete tests
            policy_machine.add_assignment(@u5, @group3)
            policy_machine.add_assignment(@u6, @group3)
            policy_machine.add_assignment(@group3, @preexisting_policy_class)
            policy_machine.add_assignment(@o5, @project3)
            policy_machine.add_assignment(@o6, @project3)
            policy_machine.add_assignment(@project3, @preexisting_policy_class)

            inserts = lambda do
              # Users
              @u1 = policy_machine.create_user('u1')
              @u2 = policy_machine.create_user('u2')
              @u3 = policy_machine.create_user('u3')

              # Objects
              @o1 = policy_machine.create_object('o1')
              @o2 = policy_machine.create_object('o2')
              @o3 = policy_machine.create_object('o3')

              # User Attributes
              @group1 = policy_machine.create_user_attribute('Group1')
              @group2 = policy_machine.create_user_attribute('Group2')
              @division = policy_machine.create_user_attribute('Division')

              # Object Attributes
              @project1 = policy_machine.create_object_attribute('Project1')
              @project2 = policy_machine.create_object_attribute('Project2')
              @projects = policy_machine.create_object_attribute('Projects')

              # Operations & Sets
              @reader = policy_machine.create_operation_set('reader')
              @writer = policy_machine.create_operation_set('writer')
              @r = policy_machine.create_operation('read')
              @w = policy_machine.create_operation('write')

              # Policy Classes
              @ou = policy_machine.create_policy_class("OU")

              # Assignments
              policy_machine.add_assignment(@u1, @group1)
              policy_machine.add_assignment(@u2, @group2)
              policy_machine.add_assignment(@u3, @division)
              policy_machine.add_assignment(@group1, @division)
              policy_machine.add_assignment(@group2, @division)
              policy_machine.add_assignment(@o1, @project1)
              policy_machine.add_assignment(@o2, @project1)
              policy_machine.add_assignment(@o3, @project2)
              policy_machine.add_assignment(@project1, @projects)
              policy_machine.add_assignment(@project2, @projects)
              policy_machine.add_assignment(@division, @ou)
              policy_machine.add_assignment(@projects, @ou)

              #Assignments for preexisting objects
              policy_machine.add_assignment(@u4, @preexisting_group)
              policy_machine.add_assignment(@o4, @preexisting_project)
              policy_machine.add_assignment(@preexisting_project, @preexisting_policy_class)
              policy_machine.add_assignment(@preexisting_group, @preexisting_policy_class)

              # Updates of preexisting elements
              @o4.update(foo: 'bar', color: 'purple')
              @u4.update(foo: 'bar', color: 'purple')
              @preexisting_group.update(foo: 'bar', color: 'purple')
              @preexisting_project.update(foo: 'bar', color: 'purple')

              #Associations for preexisting objects
              policy_machine.add_association(@preexisting_group, Set.new([@e]), @editor, @preexisting_project)

              # Associations
              policy_machine.add_association(@group1, Set.new([@w]), @writer, @project1)
              policy_machine.add_association(@group2, Set.new([@w]), @writer, @project2)
              policy_machine.add_association(@division, Set.new([@r]), @editor, @projects)

              [@u5, @u6, @o5, @o6, @group3, @project3].each(&:delete)
            end

            if bulk_create_mode
              policy_machine.bulk_persist(&inserts)
            else
              inserts.call
            end
          end

          PolicyMachine::POLICY_ELEMENT_TYPES.each do |type|
            let(:document) { {'some' => 'hash'}}

            before do
              inserts = lambda do
                policy_machine.send("create_#{type}", SecureRandom.uuid, {document: document})
              end

              @obj = if bulk_create_mode
                policy_machine.bulk_persist(&inserts)
              else
                inserts.call
              end
            end

            it 'persists arbitrary documents correctly' do
              expect(@obj.document).to eq document
            end
          end


          it 'returns all and only these privileges encoded by the policy machine' do
            expected_privileges = [
              [@u1, @w, @o1], [@u1, @w, @o2], [@u1, @r, @o1], [@u1, @r, @o2], [@u1, @r, @o3],
              [@u2, @w, @o3], [@u2, @r, @o1], [@u2, @r, @o2], [@u2, @r, @o3],
              [@u3, @r, @o1], [@u3, @r, @o2], [@u3, @r, @o3], [@u4, @e, @o4]
            ]

            assert_pm_privilege_expectations(policy_machine.privileges, expected_privileges)
          end

          it 'updates policy element attributes appropriately' do
            [@o4, @u4, @preexisting_group, @preexisting_project].each do |el|
              expect(el.foo).to eq 'bar'
              expect(el.color).to eq 'purple'
            end
          end

          it 'deletes appropriate elements' do
            [@u5, @u6, @o5, @o6, @group3, @project3].each do |el|
              meth  = el.class.to_s.split("::").last.underscore.pluralize
              match = policy_machine.send(meth, {unique_identifier: el.unique_identifier})
              expect(match).to be_empty
            end
          end

        end
      end
    end

    describe 'The Mail System:  Figure 8. (pg. 43)' do
      before do
        # Users
        @u2 = policy_machine.create_user('u2')

        # Objects
        @in_u2 = policy_machine.create_object('In u2')
        @out_u2 = policy_machine.create_object('Out u2')
        @draft_u2 = policy_machine.create_object('Draft u2')
        @trash_u2 = policy_machine.create_object('Trash u2')

        # User Attributes
        @id_u2 = policy_machine.create_user_attribute('ID u2')
        @users = policy_machine.create_user_attribute('Users')

        # Object Attributes
        @inboxes = policy_machine.create_object_attribute('Inboxes')
        @outboxes = policy_machine.create_object_attribute('Outboxes')
        @other_u2 = policy_machine.create_object_attribute('Other u2')
        @objects = policy_machine.create_object_attribute('Objects')

        # Operations & Sets
        @r = policy_machine.create_operation('read')
        @w = policy_machine.create_operation('write')
        @prohibitor = policy_machine.create_operation_set('prohibitor')
        @reader_writer = policy_machine.create_operation_set('reader_writer')
        @writer = policy_machine.create_operation_set('writer')

        # Policy Classes
        @mail_system = policy_machine.create_policy_class('Mail System')

        # Assignments
        policy_machine.add_assignment(@u2, @id_u2)
        policy_machine.add_assignment(@id_u2, @users)
        policy_machine.add_assignment(@in_u2, @inboxes)
        policy_machine.add_assignment(@out_u2, @outboxes)
        policy_machine.add_assignment(@draft_u2, @other_u2)
        policy_machine.add_assignment(@trash_u2, @other_u2)
        policy_machine.add_assignment(@inboxes, @objects)
        policy_machine.add_assignment(@outboxes, @objects)
        policy_machine.add_assignment(@users, @mail_system)
        policy_machine.add_assignment(@objects, @mail_system)

        # Associations
        policy_machine.add_association(@id_u2, Set.new([@r,@w.prohibition]), @prohibitor, @in_u2)
        policy_machine.add_association(@id_u2, Set.new([@r, @w]), @reader_writer, @out_u2)
        policy_machine.add_association(@id_u2, Set.new([@w]), @writer, @inboxes)
        policy_machine.add_association(@id_u2, Set.new([@r, @w]), @reader_writer, @other_u2)
      end

      it 'returns all and only these privileges encoded by the policy machine' do
        expected_privileges = [
          [@u2, @r, @in_u2], [@u2, @r, @out_u2], [@u2, @w, @out_u2], [@u2, @r, @draft_u2],
          [@u2, @w, @draft_u2], [@u2, @r, @trash_u2], [@u2, @w, @trash_u2]
        ]

        assert_pm_privilege_expectations(policy_machine.privileges, expected_privileges)
      end

      it 'can ignore prohibitions' do
        expect(policy_machine.is_privilege_ignoring_prohibitions?(@u2, @w, @in_u2)).to be
        ignoring_prohibitions = policy_machine.scoped_privileges(@u2, @in_u2, ignore_prohibitions: true).map{ |_,op,_| op.unique_identifier }
        with_prohibitions = policy_machine.scoped_privileges(@u2, @in_u2).map{ |_,op,_| op.unique_identifier }
        expect(ignoring_prohibitions - with_prohibitions).to eq([@w.unique_identifier])
      end
    end

    describe 'The DAC Operating System:  Figure 11. (pg. 47)' do
      before do
        # Users
        @u1 = policy_machine.create_user('u1')
        @u2 = policy_machine.create_user('u2')

        # Objects
        @o11 = policy_machine.create_object('o11')
        @o12 = policy_machine.create_object('o12')

        # User Attributes
        @id_u1 = policy_machine.create_user_attribute('ID u1')
        @id_u2 = policy_machine.create_user_attribute('ID u2')
        @users = policy_machine.create_user_attribute('Users')

        # Object Attributes
        @home_u1 = policy_machine.create_object_attribute('Home u1')
        @home_u2 = policy_machine.create_object_attribute('Home u2')
        @objects = policy_machine.create_object_attribute('Objects')

        # Operations
        @r = policy_machine.create_operation('read')
        @w = policy_machine.create_operation('write')
        @e = policy_machine.create_operation('execute')
        @can_do_attitude = policy_machine.create_operation_set('can_do_attitude')

        # Policy Classes
        @dac = policy_machine.create_policy_class('DAC')

        # Assignments
        policy_machine.add_assignment(@u1, @id_u1)
        policy_machine.add_assignment(@u2, @id_u2)
        policy_machine.add_assignment(@id_u1, @users)
        policy_machine.add_assignment(@id_u2, @users)
        policy_machine.add_assignment(@o11, @home_u1)
        policy_machine.add_assignment(@o12, @home_u1)
        policy_machine.add_assignment(@home_u1, @objects)
        policy_machine.add_assignment(@home_u2, @objects)
        policy_machine.add_assignment(@users, @dac)
        policy_machine.add_assignment(@objects, @dac)

        # Associations
        policy_machine.add_association(@id_u1, Set.new([@r, @w, @e]), @can_do_attitude, @home_u1)
        policy_machine.add_association(@id_u2, Set.new([@r, @w, @e]), @can_do_attitude, @home_u2)
      end

      it 'returns all and only these privileges encoded by the policy machine' do
        expected_privileges = [
          [@u1, @r, @o11], [@u1, @w, @o11], [@u1, @e, @o11],
          [@u1, @r, @o12], [@u1, @w, @o12], [@u1, @e, @o12],
        ]

        assert_pm_privilege_expectations(policy_machine.privileges, expected_privileges)
      end
    end

    describe 'simple multiple policy class machine' do
      before do
        # Users
        @u1 = policy_machine.create_user('u1')

        # Objects
        @o1 = policy_machine.create_object('o1')

        # User Attributes
        @ua = policy_machine.create_user_attribute('UA')

        # Object Attributes
        @oa1 = policy_machine.create_object_attribute('OA1')
        @oa2 = policy_machine.create_object_attribute('OA2')

        # Operations
        @r = policy_machine.create_operation('read')
        @w = policy_machine.create_operation('write')
        @reader = policy_machine.create_operation_set('reader')
        @reader_writer = policy_machine.create_operation_set('reader_writer')

        # Policy Classes
        @pc1 = policy_machine.create_policy_class('pc1')
        @pc2 = policy_machine.create_policy_class('pc2')

        # Assignments
        policy_machine.add_assignment(@u1, @ua)
        policy_machine.add_assignment(@o1, @oa1)
        policy_machine.add_assignment(@o1, @oa2)
        policy_machine.add_assignment(@oa1, @pc1)
        policy_machine.add_assignment(@oa2, @pc2)

        # Associations
        policy_machine.add_association(@ua, Set.new([@r]), @reader, @oa1)
        policy_machine.add_association(@ua, Set.new([@r, @w]), @reader_writer, @oa2)
      end

      it 'returns all and only these privileges encoded by the policy machine' do
        expected_privileges = [
          [@u1, @r, @o1]
        ]
        assert_pm_privilege_expectations(policy_machine.privileges, expected_privileges)
      end
    end

    describe 'accessible_objects' do

      before do
        @one_fish = policy_machine.create_object('one:fish')
        @two_fish = policy_machine.create_object('two:fish')
        @red_one = policy_machine.create_object('red:one')
        @reader = policy_machine.create_operation_set('reader')
        @read = policy_machine.create_operation('read')
        @writer = policy_machine.create_operation_set('writer')
        @write = policy_machine.create_operation('write')
        @u1 = policy_machine.create_user('u1')
        @ua = policy_machine.create_user_attribute('ua')
        [@one_fish, @two_fish, @red_one].each do |object|
          policy_machine.add_association(@ua, Set.new([@read]), @reader, object)
        end
        @oa = policy_machine.create_object_attribute('oa')
        policy_machine.add_association(@ua, Set.new([@write]), @writer, @oa)
        policy_machine.add_assignment(@u1, @ua)
        policy_machine.add_assignment(@red_one, @oa)
      end

      it 'lists all objects with the given privilege for the given user' do
        expect( policy_machine.accessible_objects(@u1, @read, key: :unique_identifier).map(&:unique_identifier) ).to include('one:fish','two:fish','red:one')
        expect( policy_machine.accessible_objects(@u1, @write, key: :unique_identifier).map(&:unique_identifier) ).to eq( ['red:one'] )
      end

      it 'filters objects via substring matching' do
        expect( policy_machine.accessible_objects(@u1, @read, includes: 'fish', key: :unique_identifier).map(&:unique_identifier) ).to match_array(['one:fish','two:fish'])
        expect( policy_machine.accessible_objects(@u1, @read, includes: 'one', key: :unique_identifier).map(&:unique_identifier) ).to match_array(['one:fish','red:one'])
      end

      context 'with prohibitions' do
        before do
          @oa2 = policy_machine.create_object_attribute('oa2')
          policy_machine.add_assignment(@one_fish, @oa2)
          @cant_read = policy_machine.create_operation_set('cant_read')
          policy_machine.add_association(@ua, Set.new([@read.prohibition]), @cant_read, @oa2)
        end

        it 'filters out prohibited objects by default' do
          expect( policy_machine.accessible_objects(@u1, @read).map(&:unique_identifier) ).to match_array(['two:fish','red:one'])
        end

        it 'can ignore prohibitions' do
          expect( policy_machine.accessible_objects(@u1, @read, ignore_prohibitions: true).map(&:unique_identifier) ).to match_array(['one:fish', 'two:fish','red:one'])
        end

      end

    end


    describe 'batch_find' do

      before do
        @one_fish = policy_machine.create_object('one:fish')
        @two_fish = policy_machine.create_object('two:fish')
        @red_one = policy_machine.create_object('red:one')
        @reader = policy_machine.create_operation_set('reader')
        @read = policy_machine.create_operation('read')
        @writer = policy_machine.create_operation_set('writer')
        @write = policy_machine.create_operation('write')
        @u1 = policy_machine.create_user('u1')
        @ua = policy_machine.create_user_attribute('ua')
        [@one_fish, @two_fish, @red_one].each do |object|
          policy_machine.add_association(@ua, Set.new([@read]), @reader, object)
        end
        @oa = policy_machine.create_object_attribute('oa')
        policy_machine.add_association(@ua, Set.new([@write]), @writer, @oa)
        policy_machine.add_assignment(@u1, @ua)
        policy_machine.add_assignment(@red_one, @oa)
      end

      context 'when given a block' do

        it 'calls the block' do
          expect do |spy|
            policy_machine.batch_find(type: :object, query: { unique_identifier: 'one:fish' }, &spy)
          end.to yield_control
        end

        context 'and search terms' do
          it 'returns the matching records' do
            policy_machine.batch_find(type: :object, query: { unique_identifier: 'one:fish' }) do |batch|
              expect(batch.size).to eq 1
              expect(batch.first.unique_identifier).to eq 'one:fish'
              expect(batch.first).to be_a(PM::Object)
            end
          end
        end

        context 'and config options' do
          it 'returns the correct batch size' do
            policy_machine.batch_find(type: :object, config: { batch_size: 1 }) do |batch|
              expect(batch.size).to eq 1
            end

            policy_machine.batch_find(type: :object, config: { batch_size: 3 }) do |batch|
              expect(batch.size).to eq 3
            end
          end
        end
      end

      context 'when not given a block' do

        it 'returns an enumerator' do
          result = policy_machine.batch_find(type: :object)
          expect(result).to be_a Enumerator
        end

        it 'the results are chainable and returns the relevant results' do
          enum = policy_machine.batch_find(type: :object)
          results = enum.flat_map do |batch|
            batch.map { |pe| pe.unique_identifier }
          end
          expected = %w(one:fish two:fish red:one)
          expect(results).to include(*expected)
        end

        context 'but given search terms' do
          it 'the results are chainable and returns the relevant results' do
            enum = policy_machine.batch_find(type: :object, query: { unique_identifier: 'one:fish' })
          results = enum.flat_map do |batch|
            batch.map { |pe| pe.unique_identifier }
          end
            expected = 'one:fish'
            expect(results.first).to eq(expected)
          end
        end

        context 'but given config options' do
          it 'respects batch size configs while return all results' do
            enum = policy_machine.batch_find(type: :object, config: { batch_size: 3})
            results = enum.flat_map do |batch|
              expect(batch.size).to eq 3
              batch.map { |pe| pe.unique_identifier }
            end
            expected = %w(one:fish two:fish red:one)
            expect(results).to include(*expected)
          end
        end

      end
    end

    describe 'batch_pluck' do
      before do
        @one_fish = policy_machine.create_object('one:fish')
        @two_fish = policy_machine.create_object('two:fish')
        @red_one = policy_machine.create_object('red:one')
        @blue_one = policy_machine.create_object('blue:one', { color: 'blue' })
      end

      context 'when given a block' do

        it 'calls the block' do
          expect do |spy|
            policy_machine.batch_pluck(type: :object, query: { unique_identifier: 'one:fish' }, fields: [:unique_identifier], &spy)
          end.to yield_control
        end

        context 'and search terms' do
          it 'returns the matching attributes' do
            policy_machine.batch_pluck(type: :object, query: { unique_identifier: 'one:fish' }, fields: [:unique_identifier]) do |batch|
              expect(batch.size).to eq 1
              expect(batch.first[:unique_identifier]).to eq 'one:fish'
            end
          end

          it 'does not return non-specified attributes' do
            policy_machine.batch_pluck(type: :object, query: { unique_identifier: 'blue:one' }, fields: [:unique_identifier]) do |batch|
              expect(batch.size).to eq 1
              expect(batch.first[:unique_identifier]).to eq 'blue:one'
              expect(batch.first).not_to have_key(:type)
              expect(batch.first).not_to have_key(:color)
            end
          end
        end

        context 'and config options' do
          it 'returns the correct batch size' do
            policy_machine.batch_pluck(type: :object, fields: [:unique_identifier], config: { batch_size: 1 }) do |batch|
              expect(batch.size).to eq 1
            end

            policy_machine.batch_pluck(type: :object, fields: [:unique_identifier], config: { batch_size: 4 }) do |batch|
              expect(batch.size).to eq 4
            end
          end
        end
      end

      context 'when not given a block' do

        it 'returns an enumerator' do
          result = policy_machine.batch_pluck(type: :object, fields: [:unique_identifier])
          expect(result).to be_a Enumerator
        end

        it 'the results are chainable and returns the relevant results' do
          enum = policy_machine.batch_pluck(type: :object, fields: [:unique_identifier])
          results = enum.flat_map do |batch|
            batch.map { |pe| pe[:unique_identifier] }
          end
          expected = %w(one:fish two:fish red:one)
          expect(results).to include(*expected)
        end

        context 'but given search terms' do
          it 'the results are chainable and returns the relevant results' do
            enum = policy_machine.batch_pluck(type: :object, query: { unique_identifier: 'one:fish' }, fields: [:unique_identifier])
          results = enum.flat_map do |batch|
            batch.map { |pe| pe[:unique_identifier] }
          end
            expected = 'one:fish'
            expect(results.first).to eq(expected)
          end
        end

        context 'but given config options' do
          it 'respects batch size configs while returning all results' do
            enum = policy_machine.batch_pluck(type: :object, fields: [:unique_identifier], config: { batch_size: 4 })
            results = enum.flat_map do |batch|
              expect(batch.size).to eq 4
              batch.map { |pe| pe[:unique_identifier] }
            end
            expected = %w(one:fish two:fish red:one)
            expect(results).to include(*expected)
          end
        end

      end
    end

    describe 'find_all_of_type' do

      it 'warns once when filtering on an extra attribute' do
        expect(Warn).to receive(:warn).once
        2.times do
          expect(policy_machine_storage_adapter.find_all_of_type_user(foo: 'bar')).to be_empty
        end
      end

      context 'an extra attribute column has been added to the database' do

        it 'does not warn' do
          expect(Warn).to_not receive(:warn)
          expect(policy_machine_storage_adapter.find_all_of_type_user(color: 'red')).to be_empty
        end

        it 'only returns elements that match the hash' do
          policy_machine_storage_adapter.add_object('some_uuid1', 'some_policy_machine_uuid1')
          policy_machine_storage_adapter.add_object('some_uuid2', 'some_policy_machine_uuid1', color: 'red')
          policy_machine_storage_adapter.add_object('some_uuid3', 'some_policy_machine_uuid1', color: 'blue')
          expect(policy_machine_storage_adapter.find_all_of_type_object(color: 'red')).to be_one
          expect(policy_machine_storage_adapter.find_all_of_type_object(color: nil)).to be_one
          expect(policy_machine_storage_adapter.find_all_of_type_object(color: 'green')).to be_none
          expect(policy_machine_storage_adapter.find_all_of_type_object(color: 'blue').map(&:color)).to eq(['blue'])
        end

        context 'pagination' do
          before do
            10.times {|i| policy_machine_storage_adapter.add_object("uuid_#{i}", 'some_policy_machine_uuid1', color: 'red') }
          end

          it 'paginates the results based on page and per_page' do
            results = policy_machine_storage_adapter.find_all_of_type_object(color: 'red', per_page: 2, page: 3)
            expect(results.first.unique_identifier).to eq "uuid_4"
            expect(results.last.unique_identifier).to eq "uuid_5"
          end

          # TODO: Investigate why this doesn't fail when not slicing params
          it 'does not paginate if no page or per_page' do
            results = policy_machine_storage_adapter.find_all_of_type_object(color: 'red').sort
            expect(results.first.unique_identifier).to eq "uuid_0"
            expect(results.last.unique_identifier).to eq "uuid_9"
          end

          it 'defaults to page 1 if no page' do
            results = policy_machine_storage_adapter.find_all_of_type_object(color: 'red', per_page: 3)
            expect(results.first.unique_identifier).to eq "uuid_0"
            expect(results.last.unique_identifier).to eq "uuid_2"
          end
        end
      end

      describe 'bulk_deletion' do
        let(:pm) { PolicyMachine.new(name: 'AR PM 1', storage_adapter: PolicyMachineStorageAdapter::ActiveRecord) }
        let(:pm2) { PolicyMachine.new(name: 'AR PM 2', storage_adapter: PolicyMachineStorageAdapter::ActiveRecord) }
        let(:user) { pm.create_user('user') }
        let(:pm2_user) { pm2.create_user('PM 2 user') }
        let(:operation) { pm.create_operation('operation') }
        let(:op_set) { pm.create_operation_set('op_set')}
        let(:user_attribute) { pm.create_user_attribute('user_attribute') }
        let(:object_attribute) { pm.create_object_attribute('object_attribute') }
        let(:object) { pm.create_object('object') }

        it 'deletes only those assignments that were on deleted elements' do
          pm.add_assignment(user, user_attribute)
          pm.add_association(user_attribute, Set.new([operation]), op_set, object_attribute)
          pm.add_assignment(object, object_attribute)

          expect(pm.is_privilege?(user, operation, object)).to be

          elt = pm.create_object(user.stored_pe.id.to_s)
          pm.bulk_persist { elt.delete }

          expect(pm.is_privilege?(user, operation, object)).to be
        end

        it 'deletes only those links that were on deleted elements' do
          pm.add_link(user, pm2_user)
          pm.add_link(pm2_user, operation)

          expect(user.linked?(operation)).to eq true
          pm.bulk_persist { operation.delete }
          expect(user.linked?(pm2_user)).to eq true
        end
      end

      describe '#bulk_persist' do
        let(:pm) { PolicyMachine.new(name: 'AR PM', storage_adapter: PolicyMachineStorageAdapter::ActiveRecord) }
        let(:user) { pm.create_user('alice') }
        let(:caffeinated) { pm.create_user_attribute('caffeinated') }
        let(:decaffeinated) { pm.create_user_attribute('decaffeinated') }

        describe 'policy element behavior' do
          it 'deletes a policy element that has been created and then deleted ' do
            user, attribute = pm.bulk_persist do
              user = pm.create_user('alice')
              attribute = pm.create_user_attribute('caffeinated')
              user.delete

              [user, attribute]
            end

            expect(pm.user_attributes).to eq [attribute]
            expect(pm.users).to be_empty
          end

          it 'deletes preexisting policy elements that have been updated' do
            user = pm.create_user('alice')
            attribute = pm.bulk_persist do
              user.update(color: 'blue')
              user.delete
              pm.create_user_attribute('caffeinated')
            end

            expect(pm.user_attributes).to eq [attribute]
            expect(pm.users).to be_empty
          end

          it 'creates a record if the record is created, deleted and then recreated' do
            user, attribute = pm.bulk_persist do
              pm.create_user('alice').delete
              attribute = pm.create_user_attribute('caffeinated')
              user = pm.create_user('alice')

              [user, attribute]
            end

            expect(pm.user_attributes).to eq [attribute]
            expect(pm.users).to eq [user]
          end

          it 'creates a record if a preexisting record is deleted and then recreated' do
            user = pm.create_user('alice')

            user, attribute = pm.bulk_persist do
              user.delete
              attribute = pm.create_user_attribute('caffeinated')
              user = pm.create_user('alice')

              [user, attribute]
            end

            expect(pm.user_attributes).to eq [attribute]
            expect(pm.users).to eq [user]
          end
        end

        describe 'assignment behavior' do
          it 'deletes assignments that have been created and then deleted' do
            pm.bulk_persist do
              user.assign_to(caffeinated)
              user.assign_to(decaffeinated)
              caffeinated.assign_to(decaffeinated)
              caffeinated.unassign(decaffeinated)
            end

            expect(user.connected?(decaffeinated)).to be true
            expect(user.connected?(caffeinated)).to be true
            expect(caffeinated.connected?(decaffeinated)).to be false
          end

          it 'deletes preexisting assignments removed' do
            caffeinated.assign_to(decaffeinated)
            pm.bulk_persist do
              user.assign_to(caffeinated)
              user.assign_to(decaffeinated)
              caffeinated.unassign(decaffeinated)
            end

            expect(user.connected?(caffeinated)).to be true
            expect(caffeinated.connected?(decaffeinated)).to be false
          end

          it 'creates an assignment if the assignment is created, deleted and then recreated' do
            pm.bulk_persist do
              user.assign_to(caffeinated)
              user.assign_to(decaffeinated)
              user.unassign(caffeinated)
              user.unassign(decaffeinated)
              user.assign_to(caffeinated)
            end

            expect(user.connected?(caffeinated)).to be true
            expect(user.connected?(decaffeinated)).to be false
          end

          it 'creates an assigment if a preexisting assignment is deleted and then recreated' do
            user.assign_to(caffeinated)
            pm.bulk_persist do
              user.assign_to(decaffeinated)
              user.unassign(caffeinated)
              user.unassign(decaffeinated)
              user.assign_to(caffeinated)
            end

            expect(user.connected?(caffeinated)).to be true
            expect(user.connected?(decaffeinated)).to be false
          end

        end

        describe 'describe policy element association behavior' do
          let(:cup) { pm.create_object('cup') }

          context 'with duplicate prohibitions on new operations' do
            it 'creates the appropriate associations' do
              pm.bulk_persist do
                operation = pm.create_operation('drink')
                operations = [operation, PM::Prohibition.on(operation), PM::Prohibition.on(operation)]
                op_set = pm.create_operation_set('new_op_set')
                pm.add_association(caffeinated, Set.new(operations), op_set, cup)
              end

              associated_operation_strings = pm.policy_machine_storage_adapter.associations_with(caffeinated.stored_pe).first.second.to_a.map(&:unique_identifier)
              expect(associated_operation_strings).to match_array ['drink', '~drink']
            end
          end
        end

        describe 'link behavior' do
          let(:mirror_pm) { PolicyMachine.new(name: 'Mirror PM', storage_adapter: PolicyMachineStorageAdapter::ActiveRecord) }
          let(:mirror_user) { mirror_pm.create_user('bob') }
          let(:has_a_goatee) { mirror_pm.create_user_attribute('evil_goatee') }
          let(:is_evil) { mirror_pm.create_user_attribute('is_evil') }

          it 'deletes links that have been created and the deleted' do
            pm.bulk_persist do
              user.link_to(has_a_goatee)
              user.link_to(is_evil)
              mirror_user.link_to(caffeinated)
              mirror_user.link_to(decaffeinated)

              user.unlink(has_a_goatee)
              mirror_user.unlink(decaffeinated)
            end

            expect(user.linked?(is_evil)).to be true
            expect(user.linked?(has_a_goatee)).to be false
            expect(mirror_user.linked?(caffeinated)).to be true
            expect(mirror_user.linked?(decaffeinated)).to be false
          end

          it 'deletes preexisting links removed' do
            user.link_to(has_a_goatee)
            mirror_user.link_to(caffeinated)

            pm.bulk_persist do
              user.link_to(is_evil)
              mirror_user.link_to(decaffeinated)

              user.unlink(has_a_goatee)
              mirror_user.unlink(decaffeinated)
            end

            expect(user.linked?(is_evil)).to be true
            expect(user.linked?(has_a_goatee)).to be false
            expect(mirror_user.linked?(caffeinated)).to be true
            expect(mirror_user.linked?(decaffeinated)).to be false
          end

          it 'creates a link if the link is created, deleted, and then recreated' do
            pm.bulk_persist do
              user.link_to(has_a_goatee)
              user.link_to(is_evil)
              mirror_user.link_to(caffeinated)
              mirror_user.link_to(decaffeinated)

              user.unlink(has_a_goatee)
              mirror_user.unlink(decaffeinated)

              user.link_to(has_a_goatee)
              mirror_user.link_to(decaffeinated)
            end

            expect(user.linked?(has_a_goatee)).to be true
            expect(user.linked?(is_evil)).to be true
            expect(mirror_user.linked?(caffeinated)).to be true
            expect(mirror_user.linked?(decaffeinated)).to be true
          end

          it 'creates a link if a preexisting assignment is deleted and then recreated' do
            user.link_to(has_a_goatee)
            mirror_user.link_to(caffeinated)

            pm.bulk_persist do
              user.link_to(is_evil)
              mirror_user.link_to(decaffeinated)

              user.unlink(has_a_goatee)
              mirror_user.unlink(decaffeinated)

              user.link_to(has_a_goatee)
              mirror_user.link_to(decaffeinated)
            end

            expect(user.linked?(has_a_goatee)).to be true
            expect(user.linked?(is_evil)).to be true
            expect(mirror_user.linked?(caffeinated)).to be true
            expect(mirror_user.linked?(decaffeinated)).to be true
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
        expect(@o1.foo).to eq 'bar'
      end

      it 'gives precedence to the column accessor' do
        @o1.color = 'Color via column'
        @o1.extra_attributes = { color: 'Color via extra_attributes' }
        @o1.save

        expect(@o1.color).to eq 'Color via column'
        expect(policy_machine_storage_adapter.find_all_of_type_object(color: 'Color via column')).to contain_exactly(@o1)
        expect(policy_machine_storage_adapter.find_all_of_type_object(color: 'Color via extra_attributes')).to be_empty
      end
    end

    context 'when there is a lot of data' do
      before do
        n = 20
        @pm = PolicyMachine.new(:name => 'ActiveRecord PM', :storage_adapter => PolicyMachineStorageAdapter::ActiveRecord)
        @u1 = @pm.create_user('u1')
        @op = @pm.create_operation('own')
        @op_set = @pm.create_operation_set('owner')
        @user_attributes = (1..n).map { |i| @pm.create_user_attribute("ua#{i}") }
        @object_attributes = (1..n).map { |i| @pm.create_object_attribute("oa#{i}") }
        @objects = (1..n).map { |i| @pm.create_object("o#{i}") }
        @user_attributes.each { |ua| @pm.add_assignment(@u1, ua) }
        @object_attributes.product(@user_attributes) { |oa, ua| @pm.add_association(ua, Set.new([@op]), @op_set, oa) }
        @object_attributes.zip(@objects) { |oa, o| @pm.add_assignment(o, oa) }
      end

      it 'does not have O(n) database calls' do
        #TODO: Find a way to count all database calls that doesn't conflict with ActiveRecord magic
        expect(PolicyMachineStorageAdapter::ActiveRecord::Assignment).to receive(:transitive_closure?).at_most(10).times
        expect(@pm.is_privilege?(@u1, @op, @objects.first)).to be true
      end
    end
  end

  describe 'relationships' do
    before do
      n = 2
      @pm = PolicyMachine.new(name: 'ActiveRecord PM', storage_adapter: PolicyMachineStorageAdapter::ActiveRecord)
      @pm2 = PolicyMachine.new(name: '2nd ActiveRecord PM', storage_adapter: PolicyMachineStorageAdapter::ActiveRecord)
      @pm3 = PolicyMachine.new(name: '3rd ActiveRecord PM', storage_adapter: PolicyMachineStorageAdapter::ActiveRecord)

      @u1 = @pm.create_user('u1')
      @pm2_u1 = @pm2.create_user('pm2 u1')

      @op = @pm.create_operation('own')
      @op_set = @pm.create_operation_set('owner')
      @pm2_op = @pm2.create_operation('pm2 op')

      @user_attributes = (1..n).map { |i| @pm.create_user_attribute("ua#{i}") }
      @ua1 = @user_attributes.first

      @object_attributes = (1..n).map { |i| @pm.create_object_attribute("oa#{i}") }
      @objects = (1..n).map { |i| @pm.create_object("o#{i}") }
      @pm3_user_attribute = @pm3.create_user_attribute('pm3_user_attribute')

      @user_attributes.each { |ua| @pm.add_assignment(@u1, ua) }
      @object_attributes.product(@user_attributes) { |oa, ua| @pm.add_association(ua, Set.new([@op]), @op_set, oa) }
      @object_attributes.zip(@objects) { |oa, o| @pm.add_assignment(o, oa) }
      @pm.add_assignment(@user_attributes.first, @user_attributes.second)

      @pm.add_link(@u1, @pm2_u1)
      @pm.add_link(@u1, @pm2_op)
      @pm.add_link(@pm2_op, @pm3_user_attribute)
    end

    describe '#descendants' do
      context 'no filter is applied' do
        # TODO normalize return value types
        it 'returns appropriate descendants' do
          expect(@u1.descendants).to match_array @user_attributes.map(&:stored_pe)
        end
      end

      context 'a filter is applied' do
        before do
          @ua1.update(color: 'green')
          @new_ua = @pm.create_user_attribute('new_ua')
          @new_ua.update(color: 'green')
          @pm.add_assignment(@u1, @new_ua)
        end

        it 'applies a single filter if one is supplied' do
          green_descendants = @u1.descendants(color: 'green')
          expect(green_descendants).to contain_exactly(@ua1.stored_pe, @new_ua.stored_pe)
        end

        it 'applies multiple filters if they are supplied' do
          green_descendants = @u1.descendants(color: 'green', unique_identifier: 'new_ua')
          expect(green_descendants).to contain_exactly(@new_ua.stored_pe)
        end

        it 'returns appropriate results when filters apply to no descendants' do
          expect(@u1.descendants(color: 'taupe')).to be_empty
          expect { @u1.descendants(not_a_real_attribute: 'fake') }.to raise_error(ArgumentError)
        end
      end
    end

    describe '#link_descendants' do
      context 'no filter is applied' do
        it 'returns appropriate cross descendants one level deep' do
          expect(@pm2_op.link_descendants).to contain_exactly(@pm3_user_attribute.stored_pe)
        end

        it 'returns appropriate cross descendants multiple levels deep' do
          desc = [@pm2_u1.stored_pe, @pm2_op.stored_pe, @pm3_user_attribute.stored_pe]
          expect(@u1.link_descendants).to match_array desc
        end
      end

      context 'a filter is applied' do
        before do
          @pm2_u1.update(color: 'blue')
          @pm2_op.update(color: 'blue')
        end

        it 'applies a single filter if one is supplied' do
          expect(@u1.link_descendants(color: 'blue')).to contain_exactly(@pm2_u1.stored_pe, @pm2_op.stored_pe)
        end

        it 'applies multiple filters if they are supplied' do
          expect(@u1.link_descendants(color: 'blue', unique_identifier: 'pm2 op')).to contain_exactly(@pm2_op.stored_pe)
        end

        it 'returns appropriate results when filters apply to no link_descendants' do
          expect(@u1.link_descendants(color: 'taupe')).to be_empty
          expect { @u1.link_descendants(not_a_real_attribute: 'fake') }.to raise_error(ArgumentError)
        end
      end
    end

    describe '#ancestors' do
      context 'no filter is applied' do
        it 'returns appropriate ancestors' do
          expect(@ua1.ancestors).to contain_exactly(@u1.stored_pe)
        end
      end

      context 'a filter is applied' do
        before do
          @u1.update(color: 'blue')
          @u2 = @pm.create_user('u2')
          @u2.update(color: 'blue')
          @pm.add_assignment(@u2, @ua1)
        end

        it 'applies a single filter if one is supplied' do
          expect(@ua1.ancestors(color: 'blue')).to contain_exactly(@u1.stored_pe, @u2.stored_pe)
        end

        it 'applies multiple filters if they are supplied' do
          expect(@ua1.ancestors(color: 'blue', unique_identifier: 'u2')).to contain_exactly(@u2.stored_pe)
        end

        it 'returns appropriate results when filters apply to no ancestors' do
          expect(@ua1.ancestors(color: 'taupe')).to be_empty
          expect { @ua1.ancestors(not_a_real_attribute: 'fake') }.to raise_error(ArgumentError)
        end
      end
    end

    describe '#link_ancestors' do
      context 'no filter is applied' do
        it 'returns appropriate cross ancestors one level deep' do
          expect(@pm2_u1.link_ancestors).to match_array [@u1.stored_pe]
        end

        it 'returns appropriate cross ancestors multiple levels deep' do
          expect(@pm3_user_attribute.link_ancestors).to match_array [@pm2_op.stored_pe, @u1.stored_pe]
        end
      end

      context 'a filter is applied' do
        before do
          @u1.update(color: 'blue')
          @pm2_op.update(color: 'blue')
        end

        it 'applies a single filter if one is supplied' do
          expect(@pm3_user_attribute.link_ancestors(color: 'blue')).to contain_exactly(@u1.stored_pe, @pm2_op.stored_pe)
        end

        it 'applies multiple filters if they are supplied' do
          expect(@pm3_user_attribute.link_ancestors(color: 'blue', unique_identifier: 'pm2 op')).to contain_exactly(@pm2_op.stored_pe)
        end

        it 'returns appropriate results when filters apply to no link_ancestors' do
          expect(@pm3_user_attribute.link_ancestors(color: 'taupe')).to be_empty
          expect { @pm3_user_attribute.link_ancestors(not_a_real_attribute: 'fake') }.to raise_error(ArgumentError)
        end
      end
    end

    describe '#parents' do
      context 'no filter is applied' do
        it 'returns appropriate parents' do
          expect(@user_attributes.second.parents).to match_array [@user_attributes.first.stored_pe, @u1.stored_pe]
        end
      end

      context 'a filter is applied' do
        before do
          @u2 = @pm.create_user('u2')
          @u3 = @pm.create_user('u3')
          @u2.update(color: 'blue')
          @u3.update(color: 'blue')
          @pm.add_assignment(@u2, @ua1)
          @pm.add_assignment(@u3, @ua1)
        end

        it 'applies a single filter if one is supplied' do
          expect(@ua1.parents(color: 'blue')).to contain_exactly(@u2.stored_pe, @u3.stored_pe)
        end

        it 'applies multiple filters if they are supplied' do
          expect(@ua1.parents(color: 'blue', unique_identifier: 'u3')).to contain_exactly(@u3.stored_pe)
        end

        it 'returns appropriate results when filters apply to no parents' do
          expect(@ua1.parents(color: 'taupe')).to be_empty
          expect { @ua1.parents(not_a_real_attribute: 'fake') }.to raise_error(ArgumentError)
        end
      end
    end

    describe '#children' do
      context 'no filter is applied' do
        it 'returns appropriate children' do
          expect(@user_attributes.first.children).to match_array [@user_attributes.second.stored_pe]
        end
      end

      context 'a filter is applied' do
        before do
          @ua1.update(color: 'green')
          @new_ua = @pm.create_user_attribute('new_ua')
          @new_ua.update(color: 'green')
          @pm.add_assignment(@u1, @new_ua)
        end

        it 'applies a single filter if one is supplied' do
          expect(@u1.children(color: 'green')).to contain_exactly(@ua1.stored_pe, @new_ua.stored_pe)
        end

        it 'applies multiple filters if they are supplied' do
          expect(@u1.children(color: 'green', unique_identifier: 'new_ua')).to contain_exactly(@new_ua.stored_pe)
        end

        it 'returns appropriate results when filters apply to no children' do
          expect(@u1.children(color: 'taupe')).to be_empty
          expect { @u1.children(not_a_real_attribute: 'fake') }.to raise_error(ArgumentError)
        end
      end
    end

    describe '#link_parents' do
      context 'no filter is applied' do
        it 'returns appropriate parents' do
          expect(@pm3_user_attribute.link_parents).to match_array [@pm2_op.stored_pe]
        end
      end

      context 'a filter is applied' do
        before do
          @pm2_op.update(color: 'green')
          @new_op = @pm2.create_operation('new_op')
          @new_op.update(color: 'green')
          @pm.add_link(@new_op, @pm3_user_attribute)
        end

        it 'applies a single filter if one is supplied' do
          expect(@pm3_user_attribute.link_parents(color: 'green')).to contain_exactly(@pm2_op.stored_pe, @new_op.stored_pe)
        end

        it 'applies multiple filters if they are supplied' do
          expect(@pm3_user_attribute.link_parents(color: 'green', unique_identifier: 'new_op')).to contain_exactly(@new_op.stored_pe)
        end

        it 'returns appropriate results when filters apply to no link_parents' do
          expect(@pm3_user_attribute.link_parents(color: 'taupe')).to be_empty
          expect { @pm3_user_attribute.link_parents(not_a_real_attribute: 'fake') }.to raise_error(ArgumentError)
        end
      end
    end

    describe '#link_children' do
      context 'no filter is applied' do
        it 'returns appropriate children' do
          expect(@u1.link_children).to match_array [@pm2_u1.stored_pe, @pm2_op.stored_pe]
        end
      end

      context 'a filter is applied' do
        before do
          @pm2_u1.update(color: 'green')
          @new_ua = @pm2.create_user_attribute('new_ua')
          @new_ua.update(color: 'green')
          @pm.add_link(@u1, @new_ua)
        end

        it 'applies a single filter if one is supplied' do
          expect(@u1.link_children(color: 'green')).to contain_exactly(@pm2_u1.stored_pe, @new_ua.stored_pe)
        end

        it 'applies multiple filters if they are supplied' do
          expect(@u1.link_children(color: 'green', unique_identifier: 'new_ua')).to contain_exactly(@new_ua.stored_pe)
        end

        it 'returns appropriate results when filters apply to no link_children' do
          expect(@u1.link_children(color: 'taupe')).to be_empty
          expect { @u1.link_children(not_a_real_attribute: 'fake') }.to raise_error(ArgumentError)
        end
      end
    end
  end

  describe 'PolicyMachine integration with PolicyMachineStorageAdapter::ActiveRecord' do
    let(:policy_machine) { PolicyMachine.new(:name => 'ActiveRecord PM', :storage_adapter => PolicyMachineStorageAdapter::ActiveRecord) }

    #TODO: move to shared example group when in memory equivalent exists
    describe '.serialize' do
      before(:all) do
        klass = PolicyMachineStorageAdapter::ActiveRecord::PolicyElement
        klass.serialize(store: :document, name: :is_arbitrary, serializer: JSON)
      end

      (PolicyMachine::POLICY_ELEMENT_TYPES).each do |type|
        describe 'store' do
          it 'can specify a root store level store supported by the backing system' do
            some_hash = {'foo' => 'bar'}
            obj = policy_machine.send("create_#{type}", SecureRandom.uuid, {document: some_hash})

            expect(obj.stored_pe.document).to eq some_hash
            expect(obj.stored_pe.extra_attributes).to be_empty
          end

          it 'can specify additional key names to be serialized' do
            pm2_hash = {'is_arbitrary' => ['thing']}
            obj = policy_machine.send("create_#{type}", SecureRandom.uuid, pm2_hash)

            expect(obj.stored_pe.is_arbitrary).to eq pm2_hash['is_arbitrary']
            expect(obj.stored_pe.document).to eq pm2_hash
            expect(obj.stored_pe.extra_attributes).to be_empty
          end
        end
      end
    end

    policy_element_types = ::PolicyMachine::POLICY_ELEMENT_TYPES

    describe 'instantiation' do
      it 'has a default name' do
        expect(PolicyMachine.new.name.length).to_not eq 0
      end

      it 'can be named' do
        ['name', :name].each do |key|
          expect(PolicyMachine.new(key => 'my name').name).to eq 'my name'
        end
      end

      it 'sets the uuid if not specified' do
        expect(PolicyMachine.new.uuid.length).to_not eq 0
      end

      it 'allows uuid to be specified' do
        ['uuid', :uuid].each do |key|
          expect(PolicyMachine.new(key => 'my uuid').uuid).to eq 'my uuid'
        end
      end

      it 'raises when uuid is blank' do
        ['', '   '].each do |blank_value|
          expect{ PolicyMachine.new(:uuid => blank_value) }.to raise_error(ArgumentError, 'uuid cannot be blank')
        end
      end

      it 'defaults to in-memory storage adapter' do
        expect(PolicyMachine.new.policy_machine_storage_adapter).to be_a(::PolicyMachineStorageAdapter::InMemory)
      end

      it 'allows user to set storage adapter' do
        ['storage_adapter', :storage_adapter].each do |key|
          storage_adapter = PolicyMachine.new(key => ::PolicyMachineStorageAdapter::Neography).policy_machine_storage_adapter
          expect(storage_adapter).to be_a(::PolicyMachineStorageAdapter::Neography)
        end
      end
    end

    describe 'Assignments' do
      allowed_assignments = [
        ['object', 'object'],
        ['object', 'object_attribute'],
        ['object_attribute', 'object_attribute'],
        ['object_attribute', 'object'],
        ['user', 'user_attribute'],
        ['user_attribute', 'user_attribute'],
        ['user_attribute', 'policy_class'],
        ['object_attribute', 'policy_class'],
        ['operation_set', 'operation_set'],
        ['operation_set', 'operation']
      ]

      # Add an assignment e.g. o -> oa or oa -> oa or u -> ua or ua -> ua.
      describe 'Adding' do
        allowed_assignments.each do |allowed_assignment|
          it "allows a #{allowed_assignment[0]} to be assigned a #{allowed_assignment[1]} (returns true)" do
            pe0 = policy_machine.send("create_#{allowed_assignment[0]}", SecureRandom.uuid)
            pe1 = policy_machine.send("create_#{allowed_assignment[1]}", SecureRandom.uuid)

            expect(policy_machine.add_assignment(pe0, pe1)).to be_truthy
          end
        end

        disallowed_assignments = policy_element_types.product(policy_element_types) - allowed_assignments
        disallowed_assignments.each do |disallowed_assignment|
          it "does not allow a #{disallowed_assignment[0]} to be assigned a #{disallowed_assignment[1]} (raises)" do
            pe0 = policy_machine.send("create_#{disallowed_assignment[0]}", SecureRandom.uuid)
            pe1 = policy_machine.send("create_#{disallowed_assignment[1]}", SecureRandom.uuid)

            expect{ policy_machine.add_assignment(pe0, pe1) }.to raise_error(ArgumentError)
          end
        end

        it 'raises when first argument is not a policy element' do
          pe = policy_machine.create_user_attribute(SecureRandom.uuid)
          expect{ policy_machine.add_assignment(1, pe) }
            .to raise_error(ArgumentError, "arg must each be a kind of PolicyElement; got #{SmallNumber} instead")
        end

        it 'raises when first argument is not in policy machine' do
          pm2 = PolicyMachine.new
          pe0 = pm2.create_user_attribute(SecureRandom.uuid)
          pe1 = policy_machine.create_user_attribute(SecureRandom.uuid)
          expect{ policy_machine.add_assignment(pe0, pe1) }
            .to raise_error(ArgumentError, "#{pe0.unique_identifier} is not in policy machine with uuid #{policy_machine.uuid}")
        end

        it 'raises when second argument is not a policy element' do
          pe = policy_machine.create_user_attribute(SecureRandom.uuid)
          expect{ policy_machine.add_assignment(pe, "hello") }
            .to raise_error(ArgumentError, "arg must each be a kind of PolicyElement; got String instead")
        end

        it 'raises when second argument is not in policy machine' do
          pm2 = PolicyMachine.new
          pe0 = policy_machine.create_user_attribute(SecureRandom.uuid)
          pe1 = pm2.create_user_attribute(SecureRandom.uuid)
          expect{ policy_machine.add_assignment(pe0, pe1) }
            .to raise_error(ArgumentError, "#{pe1.unique_identifier} is not in policy machine with uuid #{policy_machine.uuid}")
        end
      end

      describe 'Removing' do
        before do
          @pe0 = policy_machine.create_user(SecureRandom.uuid)
          @pe1 = policy_machine.create_user_attribute(SecureRandom.uuid)
        end

        it 'removes an existing assignment (returns true)' do
          policy_machine.add_assignment(@pe0, @pe1)
          expect(policy_machine.remove_assignment(@pe0, @pe1)).to be_truthy
        end

        it 'does not remove a non-existant assignment (returns false)' do
          expect(policy_machine.remove_assignment(@pe0, @pe1)).to be_falsey
        end

        it 'raises when first argument is not a policy element' do
          expect{ policy_machine.add_assignment(1, @pe1) }
            .to raise_error(ArgumentError, "arg must each be a kind of PolicyElement; got #{SmallNumber} instead")
        end

        it 'raises when first argument is not in policy machine' do
          pm2 = PolicyMachine.new
          pe0 = pm2.create_user_attribute(SecureRandom.uuid)
          pe1 = policy_machine.create_user_attribute(SecureRandom.uuid)
          expect{ policy_machine.remove_assignment(pe0, pe1) }
            .to raise_error(ArgumentError, "#{pe0.unique_identifier} is not in policy machine with uuid #{policy_machine.uuid}")
        end

        it 'raises when second argument is not a policy element' do
          expect{ policy_machine.add_assignment(@pe0, "hello") }
            .to raise_error(ArgumentError, "arg must each be a kind of PolicyElement; got String instead")
        end

        it 'raises when second argument is not in policy machine' do
          pm2 = PolicyMachine.new
          pe0 = policy_machine.create_user_attribute(SecureRandom.uuid)
          pe1 = pm2.create_user_attribute(SecureRandom.uuid)
          expect{ policy_machine.remove_assignment(pe0, pe1) }
            .to raise_error(ArgumentError, "#{pe1.unique_identifier} is not in policy machine with uuid #{policy_machine.uuid}")
        end
      end
    end

    describe 'LogicalLinks' do
      let(:pm1) { PolicyMachine.new(name: 'PM 1', storage_adapter: policy_machine.policy_machine_storage_adapter.class) }
      let(:pm2) { PolicyMachine.new(name: 'PM 2', storage_adapter: policy_machine.policy_machine_storage_adapter.class) }
      let(:pm3) { PolicyMachine.new(name: 'PM 3', storage_adapter: policy_machine.policy_machine_storage_adapter.class) }
      let(:pe1) { pm1.create_user_attribute(SecureRandom.uuid) }
      let(:pe2) { pm2.create_user_attribute(SecureRandom.uuid) }
      let(:pe3) { pm1.create_user_attribute(SecureRandom.uuid) }

      # All possible combinations of two policy machine types are allowed to be linked.
      allowed_links = policy_element_types.product(policy_element_types)

      describe 'Adding a link' do
        allowed_links.each do |aca|
          it "allows a #{aca[0]} to be assigned a #{aca[1]}" do
            policy_element1 = pm1.send("create_#{aca[0]}", SecureRandom.uuid)
            policy_element2 = pm2.send("create_#{aca[1]}", SecureRandom.uuid)

            expect { pm1.add_link(policy_element1, policy_element2) }
              .to change { policy_element1.linked?(policy_element2) }.from(false).to(true)
          end

          it "allows a #{aca[0]} to be assigned a #{aca[1]} using an unrelated policy machine" do
            policy_element1 = pm1.send("create_#{aca[0]}", SecureRandom.uuid)
            policy_element2 = pm2.send("create_#{aca[1]}", SecureRandom.uuid)

            expect { pm3.add_link(policy_element1, policy_element2) }
              .to change { policy_element1.linked?(policy_element2) }.from(false).to(true)
          end
        end

        it 'raises when the first argument is not a policy element' do
          err_msg = "args must each be a kind of PolicyElement; got a #{SmallNumber} and PM::UserAttribute instead"
          expect{ pm1.add_link(1, pe1) }.to raise_error(ArgumentError, err_msg)
        end

        it 'raises when the second argument is not a policy element' do
          err_msg = "args must each be a kind of PolicyElement; got a PM::UserAttribute and #{SmallNumber} instead"
          expect{ pm1.add_link(pe1, 1) }.to raise_error(ArgumentError, err_msg)
        end

        it 'raises when the arguments are in the same policy machine' do
          err_msg = "#{pe1.unique_identifier} and #{pe3.unique_identifier} are in the same policy machine"
          expect{ pm1.add_link(pe1, pe3) }.to raise_error(ArgumentError, err_msg)
        end
      end

      describe 'Removing a link' do
        it 'removes an existing link' do
          pm1.add_link(pe1, pe2)
          expect { pm1.remove_link(pe1, pe2) }
            .to change { pe1.linked?(pe2) }.from(true).to(false)
        end

        it 'does not remove a non-existant link' do
          expect { pm1.remove_link(pe1, pe2) }
            .to_not change { pe1.linked?(pe2) }
          expect(pe1.linked?(pe2)).to eq false
        end

        it 'raises when first argument is not a policy element' do
          err_msg = "args must each be a kind of PolicyElement; got a #{SmallNumber} and PM::UserAttribute instead"
          expect{ pm1.add_link(1, pe1) }.to raise_error(ArgumentError, err_msg)
        end

        it 'raises when the second argument is not a policy element' do
          err_msg = 'args must each be a kind of PolicyElement; got a PM::UserAttribute and String instead'
          expect{ pm1.add_link(pe1, 'pe2') }.to raise_error(ArgumentError, err_msg)
        end

        it 'raises when the first argument is in the same policy machine' do
          err_msg = "#{pe1.unique_identifier} and #{pe3.unique_identifier} are in the same policy machine"
          expect{ pm1.remove_link(pe1, pe3) }.to raise_error(ArgumentError, err_msg)
        end
      end

      describe 'bulk_persist' do
        describe 'Adding a link' do
          allowed_links.each do |aca|
            it "allows a #{aca[0]} to be assigned a #{aca[1]}" do
              policy_element1 = pm1.send("create_#{aca[0]}", SecureRandom.uuid)
              policy_element2 = pm2.send("create_#{aca[1]}", SecureRandom.uuid)

              expect do
                pm1.bulk_persist { pm1.add_link(policy_element1, policy_element2) }
              end.to change { policy_element1.linked?(policy_element2) }.from(false).to(true)
            end

            it "allows a #{aca[0]} to be assigned a #{aca[1]} using an unrelated policy machine" do
              policy_element1 = pm1.send("create_#{aca[0]}", SecureRandom.uuid)
              policy_element2 = pm2.send("create_#{aca[1]}", SecureRandom.uuid)

              expect do
                pm1.bulk_persist { pm3.add_link(policy_element1, policy_element2) }
              end.to change { policy_element1.linked?(policy_element2) }.from(false).to(true)
            end
          end

          it 'adds multiple links at once' do
            expect(pe1.linked?(pe2)).to eq false
            expect(pe2.linked?(pe3)).to eq false

            pm1.bulk_persist do
              pm1.add_link(pe1, pe2)
              pm1.add_link(pe2, pe3)
            end

            expect(pe1.linked?(pe2)).to eq true
            expect(pe2.linked?(pe3)).to eq true
          end

          it 'raises when the first argument is not a policy element' do
            err_msg = "args must each be a kind of PolicyElement; got a #{SmallNumber} and PM::UserAttribute instead"
            expect{ pm1.bulk_persist { pm1.add_link(1, pe1) } }.to raise_error(ArgumentError, err_msg)
          end

          it 'raises when the second argument is not a policy element' do
            err_msg = "args must each be a kind of PolicyElement; got a PM::UserAttribute and #{SmallNumber} instead"
            expect{ pm1.bulk_persist { pm1.add_link(pe1, 1) } }.to raise_error(ArgumentError, err_msg)
          end

          it 'raises when the arguments are in the same policy machine' do
            err_msg = "#{pe1.unique_identifier} and #{pe3.unique_identifier} are in the same policy machine"
            expect{ pm1.bulk_persist { pm1.add_link(pe1, pe3) } }.to raise_error(ArgumentError, err_msg)
          end
        end

        describe 'Removing a link' do
          it 'removes an existing link' do
            pm1.add_link(pe1, pe2)
            expect { pm1.bulk_persist { pm1.remove_link(pe1, pe2) } }
              .to change { pe1.linked?(pe2) }.from(true).to(false)
          end

          it 'removes multiple links at once' do
            pm1.add_link(pe1, pe2)
            pm1.add_link(pe2, pe3)

            expect(pe1.linked?(pe2)).to eq true
            expect(pe2.linked?(pe3)).to eq true

            pm1.bulk_persist do
              pm1.remove_link(pe1, pe2)
              pm1.remove_link(pe2, pe3)
            end

            expect(pe1.linked?(pe2)).to eq false
            expect(pe2.linked?(pe3)).to eq false
          end

          it 'does not remove a non-existant link' do
            expect { pm1.bulk_persist { pm1.remove_link(pe1, pe2) } }
              .to_not change { pe1.linked?(pe2) }
            expect(pe1.linked?(pe2)).to eq false
          end

          it 'raises when first argument is not a policy element' do
            err_msg = "args must each be a kind of PolicyElement; got a #{SmallNumber} and PM::UserAttribute instead"
            expect{ pm1.bulk_persist { pm1.add_link(1, pe1) } }.to raise_error(ArgumentError, err_msg)
          end

          it 'raises when the second argument is not a policy element' do
            err_msg = 'args must each be a kind of PolicyElement; got a PM::UserAttribute and String instead'
            expect{ pm1.bulk_persist { pm1.add_link(pe1, 'pe2') } }.to raise_error(ArgumentError, err_msg)
          end

          it 'raises when the first argument is in the same policy machine' do
            err_msg = "#{pe1.unique_identifier} and #{pe3.unique_identifier} are in the same policy machine"
            expect{ pm1.bulk_persist { pm1.remove_link(pe1, pe3) } }.to raise_error(ArgumentError, err_msg)
          end
        end
      end
    end

    describe 'Associations' do
      describe 'Adding' do
        before do
          @object_attribute = policy_machine.create_object_attribute('OA name')
          @operation_set = policy_machine.create_operation_set('reader_writer')
          @operation1 = policy_machine.create_operation('read')
          @operation2 = policy_machine.create_operation('write')
          @set_of_operation_objects = Set.new [@operation1, @operation2]
          @user_attribute = policy_machine.create_user_attribute('UA name')
        end

        it 'raises when first argument is not a PolicyElement' do
          expect{ policy_machine.add_association("234", @set_of_operation_objects, @operation_set, @object_attribute) }
            .to raise_error(ArgumentError, "arg must each be a kind of PolicyElement; got String instead")
        end

        it 'raises when first argument is not in policy machine' do
          pm2 = PolicyMachine.new
          ua = pm2.create_user_attribute(SecureRandom.uuid)
          expect{ policy_machine.add_association(ua, @set_of_operation_objects, @operation_set, @object_attribute) }
            .to raise_error(ArgumentError, "#{ua.unique_identifier} is not in policy machine with uuid #{policy_machine.uuid}")
        end

        it 'raises when third argument is not a PolicyElement' do
          expect{ policy_machine.add_association(@user_attribute, @set_of_operation_objects, @operation_set, 3) }
            .to raise_error(ArgumentError, "arg must each be a kind of PolicyElement; got #{SmallNumber} instead")
        end

        it 'raises when third argument is not in policy machine' do
          pm2 = PolicyMachine.new
          oa = pm2.create_object_attribute(SecureRandom.uuid)
          expect{ policy_machine.add_association(@user_attribute, @set_of_operation_objects, @operation_set, oa) }
            .to raise_error(ArgumentError, "#{oa.unique_identifier} is not in policy machine with uuid #{policy_machine.uuid}")
        end

        it 'allows an association to be made between an existing user_attribute, operation set and object attribute (returns true)' do
          expect(policy_machine.add_association(@user_attribute, @set_of_operation_objects, @operation_set, @object_attribute)).to be_truthy
        end

        it 'handles non-unique operation sets' do
          @set_of_operation_objects << @operation1.dup
          expect(policy_machine.add_association(@user_attribute, @set_of_operation_objects, @operation_set, @object_attribute)).to be_truthy
        end

        xit 'overwrites old associations between the same attributes' do
          first_op_set = policy_machine.create_operation_set('first_op_set')
          second_op_set = policy_machine.create_operation_set('second_op_set')
          policy_machine.add_association(@user_attribute, Set.new([@operation1]), first_op_set, @object_attribute)

          expect{policy_machine.add_association(@user_attribute, Set.new([@operation2]), second_op_set, @object_attribute)}
            .to change{ policy_machine.scoped_privileges(@user_attribute, @object_attribute) }
            .from( [[@user_attribute, @operation1, @object_attribute]] )
            .to(   [[@user_attribute, @operation2, @object_attribute]] )
        end
      end
    end

    describe 'All methods for policy elements' do
      PolicyMachine::POLICY_ELEMENT_TYPES.each do |pe_type|
        it "returns an array of all #{pe_type.to_s.pluralize}" do
          pe = policy_machine.send("create_#{pe_type}", 'some name')
          expect(policy_machine.send(pe_type.to_s.pluralize)).to eq([pe])
        end

        it "scopes by policy machine when finding an array of #{pe_type.to_s.pluralize}" do
          pe = policy_machine.send("create_#{pe_type}", 'some name')
          other_pm = PolicyMachine.new
          pe_in_other_machine = other_pm.send("create_#{pe_type}", 'some name')
          expect(policy_machine.send(pe_type.to_s.pluralize)).to eq([pe])
        end
      end
    end

    describe 'Operations' do
      it 'does not allow an operation to start with a ~' do
        expect{policy_machine.create_operation('~apple')}.to raise_error(ArgumentError)
        expect{policy_machine.create_operation('apple~')}.not_to raise_error
      end

      it 'can derive a prohibition from an operation and vice versa' do
        @op = policy_machine.create_operation('fly')
        expect(@op.prohibition).to be_prohibition
        expect(@op.prohibition.operation).to eq('fly')
      end

      it 'raises if trying to negate a non-operation' do
        expect{PM::Prohibition.on(3)}.to raise_error(ArgumentError)
      end

      it 'can negate operations expressed as strings' do
        expect(PM::Prohibition.on('fly')).to be_a String
      end

      it 'can negate operations expressed as symbols' do
        expect(PM::Prohibition.on(:fly)).to be_a Symbol
      end

      it 'can negate operations expressed as PM::Operations' do
        expect(PM::Prohibition.on(policy_machine.create_operation('fly'))).to be_a PM::Operation
      end
    end

    describe 'User Attributes' do
      describe '#extra_attributes' do
        it 'accepts and persists arbitrary extra attributes' do
          @ua = policy_machine.create_user_attribute('ua1', foo: 'bar')
          expect(@ua.foo).to eq 'bar'
          expect(policy_machine.user_attributes.last.foo).to eq 'bar'
        end
      end

      describe '#delete' do
        it 'successfully deletes itself' do
          @ua = policy_machine.create_user_attribute('ua1')
          @ua.delete
          expect(policy_machine.user_attributes).to_not include(@ua)
        end
      end
    end

    describe 'Users' do
      describe '#extra_attributes' do
        it 'accepts and persists arbitrary extra attributes' do
          @u = policy_machine.create_user('u1', foo: 'bar')
          expect(@u.foo).to eq 'bar'
          expect(policy_machine.users.last.foo).to eq 'bar'
        end

        it 'updates persisted extra attributes' do
          @u = policy_machine.create_user('u1', foo: 'bar')
          @u.update(foo: 'baz')
          expect(@u.foo).to eq 'baz'
          expect(policy_machine.users.last.foo).to eq 'baz'
        end

        it 'updates persisted extra attributes with new keys' do
          @u = policy_machine.create_user('u1', foo: 'bar')
          @u.update(foo: 'baz', bla: 'bar')
          expect(@u.foo).to eq 'baz'
          expect(policy_machine.users.last.foo).to eq 'baz'
        end

        it 'does not remove old attributes when adding new ones' do
          @u = policy_machine.create_user('u1', foo: 'bar')
          @u.update(deleted: true)
          expect(@u.foo).to eq 'bar'
          expect(policy_machine.users.last.foo).to eq 'bar'
        end

        it 'allows searching on any extra attribute keys' do
          policy_machine.create_user('u1', foo: 'bar')
          policy_machine.create_user('u2', foo: nil, attitude: 'sassy')
          silence_warnings do
            expect(policy_machine.users(foo: 'bar')).to be_one
            expect(policy_machine.users(foo: nil)).to be_one
            expect(policy_machine.users(foo: 'baz')).to be_none
            expect(policy_machine.users(foo: 'bar', attitude: 'sassy')).to be_none
          end
        end
      end
    end

    describe '#is_privilege?' do
      before do
        # Define policy elements
        @u1 = policy_machine.create_user('u1')
        @o1 = policy_machine.create_object('o1')
        @o2 = policy_machine.create_object('o2')
        @group1 = policy_machine.create_user_attribute('Group1')
        @project1 = policy_machine.create_object_attribute('Project1')
        @writer = policy_machine.create_operation_set('writer')
        @w = policy_machine.create_operation('write')

        # Assignments
        policy_machine.add_assignment(@u1, @group1)
        policy_machine.add_assignment(@o1, @project1)

        # Associations
        policy_machine.add_association(@group1, Set.new([@w]), @writer, @project1)

        # Cross Assignments included to show that privilege derivations are unaffected
        pm2 = PolicyMachine.new(name: 'Another PM', storage_adapter: policy_machine.policy_machine_storage_adapter.class)
        @another_u1 = pm2.create_user('Another u1')
        @another_o1 = pm2.create_object('Another o1')
        @another_o2 = pm2.create_object('Another o2')
        @another_group1 = pm2.create_user_attribute('Another Group1')
        @another_project1 = pm2.create_object_attribute('Another Project1')
        @another_w = pm2.create_operation('Another write')

        pm2.add_link(@u1, @another_u1)
        pm2.add_link(@o1, @another_o1)
        pm2.add_link(@o2, @another_o2)
        pm2.add_link(@group1, @another_group1)
        pm2.add_link(@project1, @another_project1)
        pm2.add_link(@w, @another_w)

        pm2.add_link(@u1, @another_group1)
        pm2.add_link(@o1, @another_project1)
        pm2.add_link(@project1, @another_w)

        pm2.add_link(@another_u1, @group1)
        pm2.add_link(@another_o1, @project1)
        pm2.add_link(@another_project1, @w)
      end

      it 'raises when the first argument is not a user or user_attribute' do
        expect{ policy_machine.is_privilege?(@o1, @w, @o1)}.
          to raise_error(ArgumentError, "user_attribute_pe must be a User or UserAttribute.")
      end

      it 'raises when the second argument is not an operation, symbol, or string' do
        expect{ policy_machine.is_privilege?(@u1, @u1, @o1)}.
          to raise_error(ArgumentError, "operation must be an Operation, Symbol, or String.")
      end

      it 'raises when the third argument is not an object or object_attribute' do
        expect{ policy_machine.is_privilege?(@u1, @w, @u1)}.
          to raise_error(ArgumentError, "object_or_attribute must either be an Object or ObjectAttribute.")
      end

      it 'returns true if privilege can be inferred from user, operation and object' do
        expect(policy_machine.is_privilege?(@u1, @w, @o1)).to be_truthy
      end

      it 'returns true if privilege can be inferred from user_attribute, operation and object' do
        expect(policy_machine.is_privilege?(@group1, @w, @o1)).to be_truthy
      end

      it 'returns true if privilege can be inferred from user, operation and object_attribute' do
        expect(policy_machine.is_privilege?(@u1, @w, @project1)).to be_truthy
      end

      it 'returns false if privilege cannot be inferred from arguments' do
        expect(policy_machine.is_privilege?(@u1, @w, @o2)).to be_falsey
      end

      it 'accepts the unique identifier for an operation in place of the operation' do
        expect(policy_machine.is_privilege?(@u1, @w.unique_identifier, @o1)).to be_truthy
      end

      it 'accepts the unique identifier in symbol form for an operation in place of the operation' do
        expect(policy_machine.is_privilege?(@u1, @w.unique_identifier.to_sym, @o1)).to be_truthy
      end

      it 'returns false on string input when the operation exists but the privilege does not' do
        expect(policy_machine.is_privilege?(@u1, @w.unique_identifier, @o2)).to be_falsey
      end

      it 'returns false on string input when the operation does not exist' do
        expect(policy_machine.is_privilege?(@u1, 'non-existent-operation', @o2)).to be_falsey
      end

      it 'does not infer privileges from deleted attributes' do
        @group1.delete
        expect(policy_machine.is_privilege?(@u1, @w, @o1)).to be_falsey
      end

      describe 'options' do
        describe 'associations' do
          it 'raises unless options[:associations] is an Array' do
            expect{ policy_machine.is_privilege?(@u1, @w, @o2, :associations => 4) }.
              to raise_error(ArgumentError, "expected options[:associations] to be an Array; got #{SmallNumber}")
          end

          it 'raises if options[:associations] is an empty array' do
            expect{ policy_machine.is_privilege?(@u1, @w, @o2, :associations => []) }.
              to raise_error(ArgumentError, "options[:associations] cannot be empty")
          end

          it 'raises unless every element of options[:associations] is a PM::Association' do
            expect{ policy_machine.is_privilege?(@u1, @w, @o2, :associations => [4]) }.
              to raise_error(ArgumentError, "expected each element of options[:associations] to be a PM::Association")
          end

          it 'raises if no element of options[:associations] contains the given operation' do
            executer = policy_machine.create_operation_set('executer')
            e = policy_machine.create_operation('execute')
            policy_machine.add_association(@group1, Set.new([e]), executer, @project1)
            expect(policy_machine.is_privilege?(@u1, @w, @o2, :associations => e.associations)).to be_falsey
          end

          it 'accepts associations in options[:associations]' do
            expect(policy_machine.is_privilege?(@u1, @w, @o1, :associations => @w.associations)).to be_truthy
          end

          it "accepts associations in options['associations']" do
            expect(policy_machine.is_privilege?(@u1, @w, @o1, 'associations' => @w.associations)).to be_truthy
          end

          it 'returns true when given association is part of the granting of a given privilege' do
            expect(policy_machine.is_privilege?(@u1, @w, @o1, 'associations' => @w.associations)).to be_truthy
          end

          it 'returns false when given association is not part of the granting of a given privilege' do
            group2 = policy_machine.create_user_attribute('Group2')

            policy_machine.add_association(group2, Set.new([@w]), @writer, @project1)
            expect(policy_machine.is_privilege?(@u1, @w, @o1, 'associations' => [@w.associations.last])).to be_falsey
          end
        end

        describe 'in_user_attribute' do
          it 'raises unless options[:in_user_attribute] is a PM::UserAttribute' do
            expect{ policy_machine.is_privilege?(@u1, @w, @o2, :in_user_attribute => 4) }.
              to raise_error(ArgumentError, "expected options[:in_user_attribute] to be a PM::UserAttribute; got #{SmallNumber}")
          end

          it 'accepts in_user_attribute in options[:in_user_attribute]' do
            expect(policy_machine.is_privilege?(@u1, @w, @o1, :in_user_attribute => @group1)).to be_truthy
          end

          it "accepts in_user_attribute in options['in_user_attribute']" do
            expect(policy_machine.is_privilege?(@group1, @w, @o1, 'in_user_attribute' => @group1)).to be_truthy
          end

          it 'returns false if given user is not in given in_user_attribute' do
            group2 = policy_machine.create_user_attribute('Group2')
            expect(policy_machine.is_privilege?(@u1, @w, @o1, 'in_user_attribute' => group2)).to be_falsey
          end
        end

        describe 'in_object_attribute' do
          it 'raises unless options[:in_object_attribute] is a PM::ObjectAttribute' do
            expect{ policy_machine.is_privilege?(@u1, @w, @o2, :in_object_attribute => 4) }.
              to raise_error(ArgumentError, "expected options[:in_object_attribute] to be a PM::ObjectAttribute; got #{SmallNumber}")
          end

          it 'accepts in_object_attribute in options[:in_object_attribute]' do
            expect(policy_machine.is_privilege?(@u1, @w, @o1, :in_object_attribute => @project1)).to be_truthy
          end

          it "accepts in_object_attribute in options['in_object_attribute']" do
            expect(policy_machine.is_privilege?(@u1, @w, @project1, 'in_object_attribute' => @project1)).to be_truthy
          end

          it 'returns false if given user is not in given in_object_attribute' do
            project2 = policy_machine.create_object_attribute('Project2')
            expect(policy_machine.is_privilege?(@u1, @w, @o1, 'in_object_attribute' => project2)).to be_falsey
          end

          it 'accepts both in_user_attribute and in_object_attribute' do
            project2 = policy_machine.create_object_attribute('Project2')
            expect(policy_machine.is_privilege?(@u1, @w, @o1, 'in_user_attribute' => @group1, 'in_object_attribute' => project2))
              .to be_falsey
          end
        end
      end
    end

    describe '#list_user_attributes' do
      before do
        # Define policy elements
        @u1 = policy_machine.create_user('u1')
        @u2 = policy_machine.create_user('u2')
        @group1 = policy_machine.create_user_attribute('Group1')
        @group2 = policy_machine.create_user_attribute('Group2')
        @subgroup1a = policy_machine.create_user_attribute('Subgroup1a')

        # Assignments
        policy_machine.add_assignment(@u1, @subgroup1a)
        policy_machine.add_assignment(@subgroup1a, @group1)
        policy_machine.add_assignment(@u2, @group2)
      end

      it 'lists the user attributes for a user' do
        expect(policy_machine.list_user_attributes(@u2)).to contain_exactly(@group2)
      end

      it 'searches multiple hops deep' do
        expect(policy_machine.list_user_attributes(@u1)).to contain_exactly(@group1, @subgroup1a)
      end

      it 'raises an argument error when passed anything other than a user' do
        expect {policy_machine.list_user_attributes(@group1)}.to raise_error ArgumentError, /Expected a PM::User/
      end
    end

    describe '#transaction' do
      it 'executes the block' do
        if_implements(policy_machine.policy_machine_storage_adapter, :transaction){}
        policy_machine.transaction do
          @oa = policy_machine.create_object_attribute('some_oa')
        end
        expect(policy_machine.object_attributes).to contain_exactly(@oa)
      end

      it 'rolls back the block on error' do
        if_implements(policy_machine.policy_machine_storage_adapter, :transaction){}
        @oa1 = policy_machine.create_object_attribute('some_oa')
        expect do
          policy_machine.transaction do
            @oa2 = policy_machine.create_object_attribute('some_other_oa')
            policy_machine.add_assignment(@oa2, :invalid_policy_class)
          end
        end.to raise_error(ArgumentError)
        expect(policy_machine.object_attributes).to contain_exactly(@oa1)
      end
    end

    describe '#privileges' do

      [nil, ' in bulk create mode'].each do |bulk_create_mode|

        # This PM is taken from the policy machine spec, Figure 4. (pg. 19)
        #TODO better cleaner stronger faster tests needed
        describe "Simple Example:  Figure 4. (pg. 19)#{bulk_create_mode}" do
          before do
            #Elements for update tests
            default_args = {foo: nil, color: nil}
            @u4 = policy_machine.create_user('u4', default_args)
            @o4 = policy_machine.create_object('o4', default_args)
            @preexisting_group = policy_machine.create_user_attribute('preexisting_group', default_args)
            @preexisting_project = policy_machine.create_object_attribute('preexisting_project', default_args)
            @preexisting_policy_class = policy_machine.create_policy_class('preexisting_policy_class', default_args)
            @editor = policy_machine.create_operation_set('editor')
            @e = policy_machine.create_operation('edit')

            # Elements for delete tests
            @u5 = policy_machine.create_user('u5')
            @u6 = policy_machine.create_user('u6')
            @o5 = policy_machine.create_object('o5')
            @o6 = policy_machine.create_object('o6')
            @group3 = policy_machine.create_user_attribute('Group3')
            @project3 = policy_machine.create_object_attribute('Project3')

            # Assignments for delete tests
            policy_machine.add_assignment(@u5, @group3)
            policy_machine.add_assignment(@u6, @group3)
            policy_machine.add_assignment(@group3, @preexisting_policy_class)
            policy_machine.add_assignment(@o5, @project3)
            policy_machine.add_assignment(@o6, @project3)
            policy_machine.add_assignment(@project3, @preexisting_policy_class)

            inserts = lambda do
              # Users
              @u1 = policy_machine.create_user('u1')
              @u2 = policy_machine.create_user('u2')
              @u3 = policy_machine.create_user('u3')

              # Objects
              @o1 = policy_machine.create_object('o1')
              @o2 = policy_machine.create_object('o2')
              @o3 = policy_machine.create_object('o3')

              # User Attributes
              @group1 = policy_machine.create_user_attribute('Group1')
              @group2 = policy_machine.create_user_attribute('Group2')
              @division = policy_machine.create_user_attribute('Division')

              # Object Attributes
              @project1 = policy_machine.create_object_attribute('Project1')
              @project2 = policy_machine.create_object_attribute('Project2')
              @projects = policy_machine.create_object_attribute('Projects')

              # Operations & Sets
              @reader = policy_machine.create_operation_set('reader')
              @writer = policy_machine.create_operation_set('writer')
              @r = policy_machine.create_operation('read')
              @w = policy_machine.create_operation('write')

              # Policy Classes
              @ou = policy_machine.create_policy_class("OU")

              # Assignments
              policy_machine.add_assignment(@u1, @group1)
              policy_machine.add_assignment(@u2, @group2)
              policy_machine.add_assignment(@u3, @division)
              policy_machine.add_assignment(@group1, @division)
              policy_machine.add_assignment(@group2, @division)
              policy_machine.add_assignment(@o1, @project1)
              policy_machine.add_assignment(@o2, @project1)
              policy_machine.add_assignment(@o3, @project2)
              policy_machine.add_assignment(@project1, @projects)
              policy_machine.add_assignment(@project2, @projects)
              policy_machine.add_assignment(@division, @ou)
              policy_machine.add_assignment(@projects, @ou)

              #Assignments for preexisting objects
              policy_machine.add_assignment(@u4, @preexisting_group)
              policy_machine.add_assignment(@o4, @preexisting_project)
              policy_machine.add_assignment(@preexisting_project, @preexisting_policy_class)
              policy_machine.add_assignment(@preexisting_group, @preexisting_policy_class)

              # Updates of preexisting elements
              @o4.update(foo: 'bar', color: 'purple')
              @u4.update(foo: 'bar', color: 'purple')
              @preexisting_group.update(foo: 'bar', color: 'purple')
              @preexisting_project.update(foo: 'bar', color: 'purple')

              #Associations for preexisting objects
              policy_machine.add_association(@preexisting_group, Set.new([@e]), @editor, @preexisting_project)

              # Associations
              policy_machine.add_association(@group1, Set.new([@w]), @writer, @project1)
              policy_machine.add_association(@group2, Set.new([@w]), @writer, @project2)
              policy_machine.add_association(@division, Set.new([@r]), @editor, @projects)

              [@u5, @u6, @o5, @o6, @group3, @project3].each(&:delete)
            end

            if bulk_create_mode
              policy_machine.bulk_persist(&inserts)
            else
              inserts.call
            end
          end

          PolicyMachine::POLICY_ELEMENT_TYPES.each do |type|
            let(:document) { {'some' => 'hash'}}

            before do
              inserts = lambda do
                policy_machine.send("create_#{type}", SecureRandom.uuid, {document: document})
              end

              @obj = if bulk_create_mode
                policy_machine.bulk_persist(&inserts)
              else
                inserts.call
              end
            end

            it 'persists arbitrary documents correctly' do
              expect(@obj.document).to eq document
            end
          end


          it 'returns all and only these privileges encoded by the policy machine' do
            expected_privileges = [
              [@u1, @w, @o1], [@u1, @w, @o2], [@u1, @r, @o1], [@u1, @r, @o2], [@u1, @r, @o3],
              [@u2, @w, @o3], [@u2, @r, @o1], [@u2, @r, @o2], [@u2, @r, @o3],
              [@u3, @r, @o1], [@u3, @r, @o2], [@u3, @r, @o3], [@u4, @e, @o4]
            ]

            assert_pm_privilege_expectations(policy_machine.privileges, expected_privileges)
          end

          it 'updates policy element attributes appropriately' do
            [@o4, @u4, @preexisting_group, @preexisting_project].each do |el|
              expect(el.foo).to eq 'bar'
              expect(el.color).to eq 'purple'
            end
          end

          it 'deletes appropriate elements' do
            [@u5, @u6, @o5, @o6, @group3, @project3].each do |el|
              meth  = el.class.to_s.split("::").last.underscore.pluralize
              match = policy_machine.send(meth, {unique_identifier: el.unique_identifier})
              expect(match).to be_empty
            end
          end

        end
      end
    end

    describe 'The Mail System:  Figure 8. (pg. 43)' do
      before do
        # Users
        @u2 = policy_machine.create_user('u2')

        # Objects
        @in_u2 = policy_machine.create_object('In u2')
        @out_u2 = policy_machine.create_object('Out u2')
        @draft_u2 = policy_machine.create_object('Draft u2')
        @trash_u2 = policy_machine.create_object('Trash u2')

        # User Attributes
        @id_u2 = policy_machine.create_user_attribute('ID u2')
        @users = policy_machine.create_user_attribute('Users')

        # Object Attributes
        @inboxes = policy_machine.create_object_attribute('Inboxes')
        @outboxes = policy_machine.create_object_attribute('Outboxes')
        @other_u2 = policy_machine.create_object_attribute('Other u2')
        @objects = policy_machine.create_object_attribute('Objects')

        # Operations & Sets
        @r = policy_machine.create_operation('read')
        @w = policy_machine.create_operation('write')
        @prohibitor = policy_machine.create_operation_set('prohibitor')
        @reader_writer = policy_machine.create_operation_set('reader_writer')
        @writer = policy_machine.create_operation_set('writer')

        # Policy Classes
        @mail_system = policy_machine.create_policy_class('Mail System')

        # Assignments
        policy_machine.add_assignment(@u2, @id_u2)
        policy_machine.add_assignment(@id_u2, @users)
        policy_machine.add_assignment(@in_u2, @inboxes)
        policy_machine.add_assignment(@out_u2, @outboxes)
        policy_machine.add_assignment(@draft_u2, @other_u2)
        policy_machine.add_assignment(@trash_u2, @other_u2)
        policy_machine.add_assignment(@inboxes, @objects)
        policy_machine.add_assignment(@outboxes, @objects)
        policy_machine.add_assignment(@users, @mail_system)
        policy_machine.add_assignment(@objects, @mail_system)

        # Associations
        policy_machine.add_association(@id_u2, Set.new([@r,@w.prohibition]), @prohibitor, @in_u2)
        policy_machine.add_association(@id_u2, Set.new([@r, @w]), @reader_writer, @out_u2)
        policy_machine.add_association(@id_u2, Set.new([@w]), @writer, @inboxes)
        policy_machine.add_association(@id_u2, Set.new([@r, @w]), @reader_writer, @other_u2)
      end

      it 'returns all and only these privileges encoded by the policy machine' do
        expected_privileges = [
          [@u2, @r, @in_u2], [@u2, @r, @out_u2], [@u2, @w, @out_u2], [@u2, @r, @draft_u2],
          [@u2, @w, @draft_u2], [@u2, @r, @trash_u2], [@u2, @w, @trash_u2]
        ]

        assert_pm_privilege_expectations(policy_machine.privileges, expected_privileges)
      end

      it 'can ignore prohibitions' do
        expect(policy_machine.is_privilege_ignoring_prohibitions?(@u2, @w, @in_u2)).to be
        ignoring_prohibitions = policy_machine.scoped_privileges(@u2, @in_u2, ignore_prohibitions: true).map{ |_,op,_| op.unique_identifier }
        with_prohibitions = policy_machine.scoped_privileges(@u2, @in_u2).map{ |_,op,_| op.unique_identifier }
        expect(ignoring_prohibitions - with_prohibitions).to eq([@w.unique_identifier])
      end
    end

    describe 'The DAC Operating System:  Figure 11. (pg. 47)' do
      before do
        # Users
        @u1 = policy_machine.create_user('u1')
        @u2 = policy_machine.create_user('u2')

        # Objects
        @o11 = policy_machine.create_object('o11')
        @o12 = policy_machine.create_object('o12')

        # User Attributes
        @id_u1 = policy_machine.create_user_attribute('ID u1')
        @id_u2 = policy_machine.create_user_attribute('ID u2')
        @users = policy_machine.create_user_attribute('Users')

        # Object Attributes
        @home_u1 = policy_machine.create_object_attribute('Home u1')
        @home_u2 = policy_machine.create_object_attribute('Home u2')
        @objects = policy_machine.create_object_attribute('Objects')

        # Operations
        @r = policy_machine.create_operation('read')
        @w = policy_machine.create_operation('write')
        @e = policy_machine.create_operation('execute')
        @can_do_attitude = policy_machine.create_operation_set('can_do_attitude')

        # Policy Classes
        @dac = policy_machine.create_policy_class('DAC')

        # Assignments
        policy_machine.add_assignment(@u1, @id_u1)
        policy_machine.add_assignment(@u2, @id_u2)
        policy_machine.add_assignment(@id_u1, @users)
        policy_machine.add_assignment(@id_u2, @users)
        policy_machine.add_assignment(@o11, @home_u1)
        policy_machine.add_assignment(@o12, @home_u1)
        policy_machine.add_assignment(@home_u1, @objects)
        policy_machine.add_assignment(@home_u2, @objects)
        policy_machine.add_assignment(@users, @dac)
        policy_machine.add_assignment(@objects, @dac)

        # Associations
        policy_machine.add_association(@id_u1, Set.new([@r, @w, @e]), @can_do_attitude, @home_u1)
        policy_machine.add_association(@id_u2, Set.new([@r, @w, @e]), @can_do_attitude, @home_u2)
      end

      it 'returns all and only these privileges encoded by the policy machine' do
        expected_privileges = [
          [@u1, @r, @o11], [@u1, @w, @o11], [@u1, @e, @o11],
          [@u1, @r, @o12], [@u1, @w, @o12], [@u1, @e, @o12],
        ]

        assert_pm_privilege_expectations(policy_machine.privileges, expected_privileges)
      end
    end

    describe 'simple multiple policy class machine' do
      before do
        # Users
        @u1 = policy_machine.create_user('u1')

        # Objects
        @o1 = policy_machine.create_object('o1')

        # User Attributes
        @ua = policy_machine.create_user_attribute('UA')

        # Object Attributes
        @oa1 = policy_machine.create_object_attribute('OA1')
        @oa2 = policy_machine.create_object_attribute('OA2')

        # Operations
        @r = policy_machine.create_operation('read')
        @w = policy_machine.create_operation('write')
        @reader = policy_machine.create_operation_set('reader')
        @reader_writer = policy_machine.create_operation_set('reader_writer')

        # Policy Classes
        @pc1 = policy_machine.create_policy_class('pc1')
        @pc2 = policy_machine.create_policy_class('pc2')

        # Assignments
        policy_machine.add_assignment(@u1, @ua)
        policy_machine.add_assignment(@o1, @oa1)
        policy_machine.add_assignment(@o1, @oa2)
        policy_machine.add_assignment(@oa1, @pc1)
        policy_machine.add_assignment(@oa2, @pc2)

        # Associations
        policy_machine.add_association(@ua, Set.new([@r]), @reader, @oa1)
        policy_machine.add_association(@ua, Set.new([@r, @w]), @reader_writer, @oa2)
      end

      it 'returns all and only these privileges encoded by the policy machine' do
        expected_privileges = [
          [@u1, @r, @o1]
        ]
        assert_pm_privilege_expectations(policy_machine.privileges, expected_privileges)
      end
    end

    describe 'accessible_objects' do

      before do
        @one_fish = policy_machine.create_object('one:fish')
        @two_fish = policy_machine.create_object('two:fish')
        @red_one = policy_machine.create_object('red:one')
        @reader = policy_machine.create_operation_set('reader')
        @read = policy_machine.create_operation('read')
        @writer = policy_machine.create_operation_set('writer')
        @write = policy_machine.create_operation('write')
        @u1 = policy_machine.create_user('u1')
        @ua = policy_machine.create_user_attribute('ua')
        [@one_fish, @two_fish, @red_one].each do |object|
          policy_machine.add_association(@ua, Set.new([@read]), @reader, object)
        end
        @oa = policy_machine.create_object_attribute('oa')
        policy_machine.add_association(@ua, Set.new([@write]), @writer, @oa)
        policy_machine.add_assignment(@u1, @ua)
        policy_machine.add_assignment(@red_one, @oa)
      end

      it 'lists all objects with the given privilege for the given user' do
        expect( policy_machine.accessible_objects(@u1, @read, key: :unique_identifier).map(&:unique_identifier) ).to include('one:fish','two:fish','red:one')
        expect( policy_machine.accessible_objects(@u1, @write, key: :unique_identifier).map(&:unique_identifier) ).to eq( ['red:one'] )
      end

      it 'filters objects via substring matching' do
        expect( policy_machine.accessible_objects(@u1, @read, includes: 'fish', key: :unique_identifier).map(&:unique_identifier) ).to match_array(['one:fish','two:fish'])
        expect( policy_machine.accessible_objects(@u1, @read, includes: 'one', key: :unique_identifier).map(&:unique_identifier) ).to match_array(['one:fish','red:one'])
      end

      context 'with prohibitions' do
        before do
          @oa2 = policy_machine.create_object_attribute('oa2')
          policy_machine.add_assignment(@one_fish, @oa2)
          @cant_read = policy_machine.create_operation_set('cant_read')
          policy_machine.add_association(@ua, Set.new([@read.prohibition]), @cant_read, @oa2)
        end

        it 'filters out prohibited objects by default' do
          expect( policy_machine.accessible_objects(@u1, @read).map(&:unique_identifier) ).to match_array(['two:fish','red:one'])
        end

        it 'can ignore prohibitions' do
          expect( policy_machine.accessible_objects(@u1, @read, ignore_prohibitions: true).map(&:unique_identifier) ).to match_array(['one:fish', 'two:fish','red:one'])
        end

      end

    end


    describe 'batch_find' do

      before do
        @one_fish = policy_machine.create_object('one:fish')
        @two_fish = policy_machine.create_object('two:fish')
        @red_one = policy_machine.create_object('red:one')
        @reader = policy_machine.create_operation_set('reader')
        @read = policy_machine.create_operation('read')
        @writer = policy_machine.create_operation_set('writer')
        @write = policy_machine.create_operation('write')
        @u1 = policy_machine.create_user('u1')
        @ua = policy_machine.create_user_attribute('ua')
        [@one_fish, @two_fish, @red_one].each do |object|
          policy_machine.add_association(@ua, Set.new([@read]), @reader, object)
        end
        @oa = policy_machine.create_object_attribute('oa')
        policy_machine.add_association(@ua, Set.new([@write]), @writer, @oa)
        policy_machine.add_assignment(@u1, @ua)
        policy_machine.add_assignment(@red_one, @oa)
      end

      context 'when given a block' do

        it 'calls the block' do
          expect do |spy|
            policy_machine.batch_find(type: :object, query: { unique_identifier: 'one:fish' }, &spy)
          end.to yield_control
        end

        context 'and search terms' do
          it 'returns the matching records' do
            policy_machine.batch_find(type: :object, query: { unique_identifier: 'one:fish' }) do |batch|
              expect(batch.size).to eq 1
              expect(batch.first.unique_identifier).to eq 'one:fish'
              expect(batch.first).to be_a(PM::Object)
            end
          end
        end

        context 'and config options' do
          it 'returns the correct batch size' do
            policy_machine.batch_find(type: :object, config: { batch_size: 1 }) do |batch|
              expect(batch.size).to eq 1
            end

            policy_machine.batch_find(type: :object, config: { batch_size: 3 }) do |batch|
              expect(batch.size).to eq 3
            end
          end
        end
      end

      context 'when not given a block' do

        it 'returns an enumerator' do
          result = policy_machine.batch_find(type: :object)
          expect(result).to be_a Enumerator
        end

        it 'the results are chainable and returns the relevant results' do
          enum = policy_machine.batch_find(type: :object)
          results = enum.flat_map do |batch|
            batch.map { |pe| pe.unique_identifier }
          end
          expected = %w(one:fish two:fish red:one)
          expect(results).to include(*expected)
        end

        context 'but given search terms' do
          it 'the results are chainable and returns the relevant results' do
            enum = policy_machine.batch_find(type: :object, query: { unique_identifier: 'one:fish' })
          results = enum.flat_map do |batch|
            batch.map { |pe| pe.unique_identifier }
          end
            expected = 'one:fish'
            expect(results.first).to eq(expected)
          end
        end

        context 'but given config options' do
          it 'respects batch size configs while return all results' do
            enum = policy_machine.batch_find(type: :object, config: { batch_size: 3})
            results = enum.flat_map do |batch|
              expect(batch.size).to eq 3
              batch.map { |pe| pe.unique_identifier }
            end
            expected = %w(one:fish two:fish red:one)
            expect(results).to include(*expected)
          end
        end

      end
    end

    describe 'batch_pluck' do
      before do
        @one_fish = policy_machine.create_object('one:fish')
        @two_fish = policy_machine.create_object('two:fish')
        @red_one = policy_machine.create_object('red:one')
        @blue_one = policy_machine.create_object('blue:one', { color: 'blue' })
      end

      context 'when given a block' do

        it 'calls the block' do
          expect do |spy|
            policy_machine.batch_pluck(type: :object, query: { unique_identifier: 'one:fish' }, fields: [:unique_identifier], &spy)
          end.to yield_control
        end

        context 'and search terms' do
          it 'returns the matching attributes' do
            policy_machine.batch_pluck(type: :object, query: { unique_identifier: 'one:fish' }, fields: [:unique_identifier]) do |batch|
              expect(batch.size).to eq 1
              expect(batch.first[:unique_identifier]).to eq 'one:fish'
            end
          end

          it 'does not return non-specified attributes' do
            policy_machine.batch_pluck(type: :object, query: { unique_identifier: 'blue:one' }, fields: [:unique_identifier]) do |batch|
              expect(batch.size).to eq 1
              expect(batch.first[:unique_identifier]).to eq 'blue:one'
              expect(batch.first).not_to have_key(:type)
              expect(batch.first).not_to have_key(:color)
            end
          end
        end

        context 'and config options' do
          it 'returns the correct batch size' do
            policy_machine.batch_pluck(type: :object, fields: [:unique_identifier], config: { batch_size: 1 }) do |batch|
              expect(batch.size).to eq 1
            end

            policy_machine.batch_pluck(type: :object, fields: [:unique_identifier], config: { batch_size: 4 }) do |batch|
              expect(batch.size).to eq 4
            end
          end
        end
      end

      context 'when not given a block' do

        it 'returns an enumerator' do
          result = policy_machine.batch_pluck(type: :object, fields: [:unique_identifier])
          expect(result).to be_a Enumerator
        end

        it 'the results are chainable and returns the relevant results' do
          enum = policy_machine.batch_pluck(type: :object, fields: [:unique_identifier])
          results = enum.flat_map do |batch|
            batch.map { |pe| pe[:unique_identifier] }
          end
          expected = %w(one:fish two:fish red:one)
          expect(results).to include(*expected)
        end

        context 'but given search terms' do
          it 'the results are chainable and returns the relevant results' do
            enum = policy_machine.batch_pluck(type: :object, query: { unique_identifier: 'one:fish' }, fields: [:unique_identifier])
          results = enum.flat_map do |batch|
            batch.map { |pe| pe[:unique_identifier] }
          end
            expected = 'one:fish'
            expect(results.first).to eq(expected)
          end
        end

        context 'but given config options' do
          it 'respects batch size configs while returning all results' do
            enum = policy_machine.batch_pluck(type: :object, fields: [:unique_identifier], config: { batch_size: 4 })
            results = enum.flat_map do |batch|
              expect(batch.size).to eq 4
              batch.map { |pe| pe[:unique_identifier] }
            end
            expected = %w(one:fish two:fish red:one)
            expect(results).to include(*expected)
          end
        end

      end
    end
  end
end
