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

  describe PolicyMachineStorageAdapter::ActiveRecord do
    it_behaves_like 'a policy machine storage adapter with required public methods'
    it_behaves_like 'a policy machine storage adapter'
    let(:policy_machine_storage_adapter) { described_class.new }

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

        it 'returns appropriate results when filters apply to all descendants' do
          all_descendants = @user_attributes.map(&:stored_pe) + [@new_ua.stored_pe]
          expect(@u1.descendants({})).to match_array(all_descendants)
          expect(@u1.descendants(policy_machine_uuid: @pm.uuid)).to match_array(all_descendants)
        end
      end
    end

    describe '#link_descendants' do
      it 'returns appropriate cross descendants' do
        desc = [@pm2_u1.stored_pe, @pm2_op.stored_pe, @pm3_user_attribute.stored_pe]
        expect(@u1.link_descendants).to match_array desc
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
          @u2 = @pm.create_user('u2')
          @u2.update(color: 'blue')
          @pm.add_assignment(@u2, @ua1)

          @u3 = @pm.create_user('u3')
          @u3.update(color: 'blue')
          @pm.add_assignment(@u3, @ua1)
        end

        it 'applies a single filter if one is supplied' do
          blue_ancestors = @ua1.ancestors(color: 'blue')
          expect(blue_ancestors).to contain_exactly(@u2.stored_pe, @u3.stored_pe)
        end

        it 'applies multiple filters if they are supplied' do
          blue_ancestors = @ua1.ancestors(color: 'blue', unique_identifier: 'u3')
          expect(blue_ancestors).to contain_exactly(@u3.stored_pe)
        end

        it 'returns appropriate results when filters apply to no ancestors' do
          expect(@ua1.ancestors(color: 'taupe')).to be_empty
          expect { @ua1.ancestors(not_a_real_attribute: 'fake') }.to raise_error(ArgumentError)
        end

        it 'returns appropriate results when filters apply to all ancestors' do
          all_ancestors = [@u1.stored_pe, @u2.stored_pe, @u3.stored_pe]
          expect(@ua1.ancestors({})).to match_array(all_ancestors)
          expect(@ua1.ancestors(policy_machine_uuid: @pm.uuid)).to match_array(all_ancestors)
        end
      end
    end

    describe '#link_ancestors' do
      it 'returns appropriate cross ancestors one level deep' do
        expect(@pm2_u1.link_ancestors).to match_array [@u1.stored_pe]
      end

      it 'returns appropriate cross ancestors multiple levels deep' do
        expect(@pm3_user_attribute.link_ancestors).to match_array [@pm2_op.stored_pe, @u1.stored_pe]
      end
    end

    describe '#parents' do
      it 'returns appropriate parents' do
        expect(@user_attributes.second.parents).to match_array [@user_attributes.first.stored_pe, @u1.stored_pe]
      end
    end

    describe '#link_parents' do
      it 'returns appropriate parents' do
        expect(@pm3_user_attribute.link_parents).to match_array [@pm2_op.stored_pe]
      end
    end

    describe '#children' do
      it 'returns appropriate children' do
        expect(@user_attributes.first.children).to match_array [@user_attributes.second.stored_pe]
      end
    end

    describe '#link_children' do
      it 'returns appropriate children' do
        expect(@u1.link_children).to match_array [@pm2_u1.stored_pe, @pm2_op.stored_pe]
      end
    end
  end

  describe 'PolicyMachine integration with PolicyMachineStorageAdapter::ActiveRecord' do
    it_behaves_like 'a policy machine' do
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
    end
  end
end
