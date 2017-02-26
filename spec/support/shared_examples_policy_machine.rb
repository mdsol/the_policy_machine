require 'spec_helper'
require_relative 'storage_adapter_helpers.rb'

policy_element_types = ::PolicyMachine::POLICY_ELEMENT_TYPES

shared_examples "a policy machine" do
  describe 'instantiation' do
    it 'has a default name' do
      PolicyMachine.new.name.length.should_not == 0
    end

    it 'can be named' do
      ['name', :name].each do |key|
        PolicyMachine.new(key => 'my name').name.should == 'my name'
      end
    end

    it 'sets the uuid if not specified' do
      PolicyMachine.new.uuid.length.should_not == 0
    end

    it 'allows uuid to be specified' do
      ['uuid', :uuid].each do |key|
        PolicyMachine.new(key => 'my uuid').uuid.should == 'my uuid'
      end
    end

    it 'raises when uuid is blank' do
      ['', '   '].each do |blank_value|
        expect{ PolicyMachine.new(:uuid => blank_value) }
          .to raise_error(ArgumentError, 'uuid cannot be blank')
      end
    end

    it 'defaults to in-memory storage adapter' do
      PolicyMachine.new.policy_machine_storage_adapter.should be_a(::PolicyMachineStorageAdapter::InMemory)
    end

    it 'allows user to set storage adapter' do
      ['storage_adapter', :storage_adapter].each do |key|
        PolicyMachine.new(key => ::PolicyMachineStorageAdapter::Neography).policy_machine_storage_adapter.
          should be_a(::PolicyMachineStorageAdapter::Neography)
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
      ['object_attribute', 'policy_class']
    ]

    # Add an assignment e.g. o -> oa or oa -> oa or u -> ua or ua -> ua.
    describe 'Adding' do
      allowed_assignments.each do |allowed_assignment|
        it "allows a #{allowed_assignment[0]} to be assigned a #{allowed_assignment[1]} (returns true)" do
          pe0 = policy_machine.send("create_#{allowed_assignment[0]}", SecureRandom.uuid)
          pe1 = policy_machine.send("create_#{allowed_assignment[1]}", SecureRandom.uuid)

          policy_machine.add_assignment(pe0, pe1).should be_true
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
          .to raise_error(ArgumentError, "arg must each be a kind of PolicyElement; got Fixnum instead")
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
        policy_machine.remove_assignment(@pe0, @pe1).should be_true
      end

      it 'does not remove a non-existant assignment (returns false)' do
        policy_machine.remove_assignment(@pe0, @pe1).should be_false
      end

      it 'raises when first argument is not a policy element' do
        expect{ policy_machine.add_assignment(1, @pe1) }
          .to raise_error(ArgumentError, "arg must each be a kind of PolicyElement; got Fixnum instead")
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

  describe 'CrossAssignments' do
    let(:pm1) { PolicyMachine.new }
    let(:pm2) { PolicyMachine.new }
    let(:pe1) { pm1.create_user_attribute(SecureRandom.uuid) }
    let(:pe2) { pm2.create_user_attribute(SecureRandom.uuid) }
    let(:pe3) { pm1.create_user_attribute(SecureRandom.uuid) }

    # All possible combinations of two policy machine types are allowed to be cross assigned.
    allowed_cross_assignments = policy_element_types.product(policy_element_types)

    describe 'Adding' do
      allowed_cross_assignments.each do |aca|
        it "allows a #{aca[0]} to be assigned a #{aca[1]}" do
          policy_element1 = pm1.send("create_#{aca[0]}", SecureRandom.uuid)
          policy_element2 = pm2.send("create_#{aca[1]}", SecureRandom.uuid)

          pm1.add_cross_assignment(policy_element1, policy_element2).should be_true
        end
      end

      it 'raises when the first argument is not a policy element' do
        err_msg = 'args must each be a kind of PolicyElement; got a Fixnum and PolicyElement instead'
        expect{ pm1.add_cross_assignment(1, pe1) }.to raise_error(ArgumentError, err_msg)
      end

      it 'raises when the second argument is not a policy element' do
        err_msg = 'args must each be a kind of PolicyElement; got a PolicyElement and Fixnum instead'
        expect{ pm1.add_cross_assignment(pe1, 1) }.to raise_error(ArgumentError, err_msg)
      end

      it 'raises when the arguments are in the same policy machine' do
        err_msg = "#{pe1.unique_identifier} and #{pe3.unique_identifier} are in the same policy machine"
        expect{ pm1.add_cross_assignment(pe1, pe3) }.to raise_error(ArgumentError, err_msg)
      end
    end

    describe 'Removing' do
      it 'removes an existing assignment' do
        pm1.add_cross_assignment(pe1, pe2)
        expect(pm1.remove_cross_assignment(pe1, pe2)).to eq true
      end

      it 'does not remove a non-existant assignment' do
        expect(pm1.remove_cross_assignment(pe1, pe2)).to eq false
      end

      it 'raises when first argument is not a policy element' do
        err_msg = 'args must each be a kind of PolicyElement; got a Fixnum and PolicyElement instead'
        expect{ pm1.add_cross_assignment(1, pe1) }.to raise_error(ArgumentError, err_msg)
      end

      it 'raises when the second argument is not a policy element' do
        err_msg = 'args must each be a kind of PolicyElement; got a PolicyElement and String instead'
        expect{ pm1.add_cross_assignment(pe1, 'pe2') }.to raise_error(ArgumentError, err_msg)
      end

      it 'raises when the first argument is in the same policy machine' do
        err_msg = "#{pe1.unique_identifier} and #{pe3.unique_identifier} are in the same policy machine"
        expect{ pm1.remove_assignment(pe, pe3) }.to raise_error(ArgumentError, err_msg)
      end
    end
  end

  describe 'Associations' do
    describe 'Adding' do
      before do
        @object_attribute = policy_machine.create_object_attribute('OA name')
        @operation1 = policy_machine.create_operation('read')
        @operation2 = policy_machine.create_operation('write')
        @operation_set = Set.new [@operation1, @operation2]
        @user_attribute = policy_machine.create_user_attribute('UA name')
      end

      it 'raises when first argument is not a PolicyElement' do
        expect{ policy_machine.add_association("234", @operation_set, @object_attribute) }
          .to raise_error(ArgumentError, "arg must each be a kind of PolicyElement; got String instead")
      end

      it 'raises when first argument is not in policy machine' do
        pm2 = PolicyMachine.new
        ua = pm2.create_user_attribute(SecureRandom.uuid)
        expect{ policy_machine.add_association(ua, @operation_set, @object_attribute) }
          .to raise_error(ArgumentError, "#{ua.unique_identifier} is not in policy machine with uuid #{policy_machine.uuid}")
      end

      it 'raises when third argument is not a PolicyElement' do
        expect{ policy_machine.add_association(@user_attribute, @operation_set, 3) }
          .to raise_error(ArgumentError, "arg must each be a kind of PolicyElement; got Fixnum instead")
      end

      it 'raises when third argument is not in policy machine' do
        pm2 = PolicyMachine.new
        oa = pm2.create_object_attribute(SecureRandom.uuid)
        expect{ policy_machine.add_association(@user_attribute, @operation_set, oa) }
          .to raise_error(ArgumentError, "#{oa.unique_identifier} is not in policy machine with uuid #{policy_machine.uuid}")
      end

      it 'allows an association to be made between an existing user_attribute, operation set and object attribute (returns true)' do
        policy_machine.add_association(@user_attribute, @operation_set, @object_attribute).should be_true
      end

      it 'handles non-unique operation sets' do
        @operation_set << @operation1.dup
        policy_machine.add_association(@user_attribute, @operation_set, @object_attribute).should be_true
      end

      it 'overwrites old associations between the same attributes' do
        policy_machine.add_association(@user_attribute, Set.new([@operation1]), @object_attribute)

        expect{policy_machine.add_association(@user_attribute, Set.new([@operation2]), @object_attribute)}
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
        policy_machine.send(pe_type.to_s.pluralize).should == [pe]
      end

      it "scopes by policy machine when finding an array of #{pe_type.to_s.pluralize}" do
        pe = policy_machine.send("create_#{pe_type}", 'some name')
        other_pm = PolicyMachine.new
        pe_in_other_machine = other_pm.send("create_#{pe_type}", 'some name')
        policy_machine.send(pe_type.to_s.pluralize).should == [pe]
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
        @ua.foo.should == 'bar'
        policy_machine.user_attributes.last.foo.should == 'bar'
      end
    end

    describe '#delete' do
      it 'successfully deletes itself' do
        @ua = policy_machine.create_user_attribute('ua1')
        @ua.delete
        policy_machine.user_attributes.should_not include(@ua)
      end
    end
  end

  describe 'Users' do
    describe '#extra_attributes' do
      it 'accepts and persists arbitrary extra attributes' do
        @u = policy_machine.create_user('u1', foo: 'bar')
        @u.foo.should == 'bar'
        policy_machine.users.last.foo.should == 'bar'
      end

      it 'updates persisted extra attributes' do
        @u = policy_machine.create_user('u1', foo: 'bar')
        @u.update(foo: 'baz')
        @u.foo.should == 'baz'
        policy_machine.users.last.foo.should == 'baz'
      end

      it 'updates persisted extra attributes with new keys' do
        @u = policy_machine.create_user('u1', foo: 'bar')
        @u.update(foo: 'baz', bla: 'bar')
        @u.foo.should == 'baz'
        policy_machine.users.last.foo.should == 'baz'
      end

      it 'does not remove old attributes when adding new ones' do
        @u = policy_machine.create_user('u1', foo: 'bar')
        @u.update(deleted: true)
        @u.foo.should == 'bar'
        policy_machine.users.last.foo.should == 'bar'
      end

      it 'allows searching on any extra attribute keys' do
        policy_machine.create_user('u1', foo: 'bar')
        policy_machine.create_user('u2', foo: nil, attitude: 'sassy')
        silence_warnings do
          policy_machine.users(foo: 'bar').should be_one
          policy_machine.users(foo: nil).should be_one
          policy_machine.users(foo: 'baz').should be_none
          policy_machine.users(foo: 'bar', attitude: 'sassy').should be_none
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
      @w = policy_machine.create_operation('write')

      # Assignments
      policy_machine.add_assignment(@u1, @group1)
      policy_machine.add_assignment(@o1, @project1)

      # Associations
      policy_machine.add_association(@group1, Set.new([@w]), @project1)
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
      policy_machine.is_privilege?(@u1, @w, @o1).should be_true
    end

    it 'returns true if privilege can be inferred from user_attribute, operation and object' do
      policy_machine.is_privilege?(@group1, @w, @o1).should be_true
    end

    it 'returns true if privilege can be inferred from user, operation and object_attribute' do
      policy_machine.is_privilege?(@u1, @w, @project1).should be_true
    end

    it 'returns false if privilege cannot be inferred from arguments' do
      policy_machine.is_privilege?(@u1, @w, @o2).should be_false
    end

    it 'accepts the unique identifier for an operation in place of the operation' do
      policy_machine.is_privilege?(@u1, @w.unique_identifier, @o1).should be_true
    end

    it 'accepts the unique identifier in symbol form for an operation in place of the operation' do
      policy_machine.is_privilege?(@u1, @w.unique_identifier.to_sym, @o1).should be_true
    end

    it 'returns false on string input when the operation exists but the privilege does not' do
      policy_machine.is_privilege?(@u1, @w.unique_identifier, @o2).should be_false
    end

    it 'returns false on string input when the operation does not exist' do
      policy_machine.is_privilege?(@u1, 'non-existent-operation', @o2).should be_false
    end

    it 'does not infer privileges from deleted attributes' do
      @group1.delete
      policy_machine.is_privilege?(@u1, @w, @o1).should be_false
    end

    describe 'options' do
      describe 'associations' do
        it 'raises unless options[:associations] is an Array' do
          expect{ policy_machine.is_privilege?(@u1, @w, @o2, :associations => 4) }.
            to raise_error(ArgumentError, "expected options[:associations] to be an Array; got Fixnum")
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
          e = policy_machine.create_operation('execute')
          policy_machine.add_association(@group1, Set.new([e]), @project1)
          policy_machine.is_privilege?(@u1, @w, @o2, :associations => e.associations).should be_false
        end

        it 'accepts associations in options[:associations]' do
          policy_machine.is_privilege?(@u1, @w, @o1, :associations => @w.associations).should be_true
        end

        it "accepts associations in options['associations']" do
          policy_machine.is_privilege?(@u1, @w, @o1, 'associations' => @w.associations).should be_true
        end

        it 'returns true when given association is part of the granting of a given privilege' do
          policy_machine.is_privilege?(@u1, @w, @o1, 'associations' => @w.associations).should be_true
        end

        it 'returns false when given association is not part of the granting of a given privilege' do
          group2 = policy_machine.create_user_attribute('Group2')

          policy_machine.add_association(group2, Set.new([@w]), @project1)
          policy_machine.is_privilege?(@u1, @w, @o1, 'associations' => [@w.associations.last]).should be_false
        end
      end

      describe 'in_user_attribute' do
        it 'raises unless options[:in_user_attribute] is a PM::UserAttribute' do
          expect{ policy_machine.is_privilege?(@u1, @w, @o2, :in_user_attribute => 4) }.
            to raise_error(ArgumentError, 'expected options[:in_user_attribute] to be a PM::UserAttribute; got Fixnum')
        end

        it 'accepts in_user_attribute in options[:in_user_attribute]' do
          policy_machine.is_privilege?(@u1, @w, @o1, :in_user_attribute => @group1).should be_true
        end

        it "accepts in_user_attribute in options['in_user_attribute']" do
          policy_machine.is_privilege?(@group1, @w, @o1, 'in_user_attribute' => @group1).should be_true
        end

        it 'returns false if given user is not in given in_user_attribute' do
          group2 = policy_machine.create_user_attribute('Group2')
          policy_machine.is_privilege?(@u1, @w, @o1, 'in_user_attribute' => group2).should be_false
        end
      end

      describe 'in_object_attribute' do
        it 'raises unless options[:in_object_attribute] is a PM::ObjectAttribute' do
          expect{ policy_machine.is_privilege?(@u1, @w, @o2, :in_object_attribute => 4) }.
            to raise_error(ArgumentError, 'expected options[:in_object_attribute] to be a PM::ObjectAttribute; got Fixnum')
        end

        it 'accepts in_object_attribute in options[:in_object_attribute]' do
          policy_machine.is_privilege?(@u1, @w, @o1, :in_object_attribute => @project1).should be_true
        end

        it "accepts in_object_attribute in options['in_object_attribute']" do
          policy_machine.is_privilege?(@u1, @w, @project1, 'in_object_attribute' => @project1).should be_true
        end

        it 'returns false if given user is not in given in_object_attribute' do
          project2 = policy_machine.create_object_attribute('Project2')
          policy_machine.is_privilege?(@u1, @w, @o1, 'in_object_attribute' => project2).should be_false
        end

        it 'accepts both in_user_attribute and in_object_attribute' do
          project2 = policy_machine.create_object_attribute('Project2')
          policy_machine.is_privilege?(@u1, @w, @o1, 'in_user_attribute' => @group1, 'in_object_attribute' => project2).
            should be_false
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
      policy_machine.list_user_attributes(@u2).should == [@group2]
    end

    it 'searches multiple hops deep' do
      policy_machine.list_user_attributes(@u1).should =~ [@group1, @subgroup1a]
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
      policy_machine.object_attributes.should == [@oa]
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
      policy_machine.object_attributes.should == [@oa1]
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

            # Operations
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
            policy_machine.add_association(@preexisting_group, Set.new([@e]), @preexisting_project)

            # Associations
            policy_machine.add_association(@group1, Set.new([@w]), @project1)
            policy_machine.add_association(@group2, Set.new([@w]), @project2)
            policy_machine.add_association(@division, Set.new([@r]), @projects)

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

      # Operations
      @r = policy_machine.create_operation('read')
      @w = policy_machine.create_operation('write')

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
      policy_machine.add_association(@id_u2, Set.new([@r,@w.prohibition]), @in_u2)
      policy_machine.add_association(@id_u2, Set.new([@r, @w]), @out_u2)
      policy_machine.add_association(@id_u2, Set.new([@w]), @inboxes)
      policy_machine.add_association(@id_u2, Set.new([@r, @w]), @other_u2)
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
      policy_machine.add_association(@id_u1, Set.new([@r, @w, @e]), @home_u1)
      policy_machine.add_association(@id_u2, Set.new([@r, @w, @e]), @home_u2)
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
      policy_machine.add_association(@ua, Set.new([@r]), @oa1)
      policy_machine.add_association(@ua, Set.new([@r, @w]), @oa2)
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
      @read = policy_machine.create_operation('read')
      @write = policy_machine.create_operation('write')
      @u1 = policy_machine.create_user('u1')
      @ua = policy_machine.create_user_attribute('ua')
      [@one_fish, @two_fish, @red_one].each do |object|
        policy_machine.add_association(@ua, Set.new([@read]), object)
      end
      @oa = policy_machine.create_object_attribute('oa')
      policy_machine.add_association(@ua, Set.new([@write]), @oa)
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
        policy_machine.add_association(@ua, Set.new([@read.prohibition]), @oa2)
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
      @read = policy_machine.create_operation('read')
      @write = policy_machine.create_operation('write')
      @u1 = policy_machine.create_user('u1')
      @ua = policy_machine.create_user_attribute('ua')
      [@one_fish, @two_fish, @red_one].each do |object|
        policy_machine.add_association(@ua, Set.new([@read]), object)
      end
      @oa = policy_machine.create_object_attribute('oa')
      policy_machine.add_association(@ua, Set.new([@write]), @oa)
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
        it 'resepects batch size configs while return all results' do
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
end
