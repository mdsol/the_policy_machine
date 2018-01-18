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
          pm.add_assignment(op_set, operation)
          pm.add_association(user_attribute, op_set, object_attribute)
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
        @pm.add_assignment(@op_set, @op)
        @object_attributes.product(@user_attributes) { |oa, ua| @pm.add_association(ua, @op_set, oa) }
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
    let(:pm1) { PolicyMachine.new(name: 'AR PM 1', storage_adapter: PolicyMachineStorageAdapter::ActiveRecord) }
    let(:pm2) { PolicyMachine.new(name: 'AR PM 2', storage_adapter: PolicyMachineStorageAdapter::ActiveRecord) }
    let(:pm3) { PolicyMachine.new(name: 'AR PM 3', storage_adapter: PolicyMachineStorageAdapter::ActiveRecord) }

    let(:user_1) { pm1.create_user('user_1') }
    let(:user_2) { pm1.create_user('user_2') }
    let(:user_3) { pm1.create_user('user_3') }
    let!(:users) { [user_1, user_2, user_3] }

    let(:operation_1) { pm1.create_operation('operation_1') }

    let(:opset_1) { pm1.create_operation_set('operation_set_1') }

    let(:user_attr_1) { pm1.create_user_attribute('user_attr_1') }
    let(:user_attr_2) { pm1.create_user_attribute('user_attr_2') }
    let(:user_attr_3) { pm1.create_user_attribute('user_attr_3') }
    let(:user_attributes) { [user_attr_1, user_attr_2, user_attr_3] }

    let(:object_attr_1) { pm1.create_object_attribute('object_attr_1') }
    let(:object_attr_2) { pm1.create_object_attribute('object_attr_2') }
    let(:object_attr_3) { pm1.create_object_attribute('object_attr_3') }
    let(:object_attr_1_1) { pm1.create_object_attribute('object_attr_1_1') }
    let(:object_attr_1_2) { pm1.create_object_attribute('object_attr_1_2') }
    let(:object_attr_1_1_1) { pm1.create_object_attribute('object_attr_1_1_1') }
    let(:object_attributes) { [object_attr_1, object_attr_2, object_attr_3] }
    let(:more_object_attributes) { [object_attr_1_1, object_attr_1_2, object_attr_1_1_1] }

    let(:object_1) { pm1.create_object('object_1') }
    let(:object_2) { pm1.create_object('object_2') }
    let(:object_3) { pm1.create_object('object_3') }
    let(:object_1_1) { pm1.create_object('object_1_1') }
    let(:object_1_2) { pm1.create_object('object_1_2') }
    let(:object_1_1_1) { pm1.create_object('object_1_1_1') }
    let(:objects) { [object_1, object_2, object_3] }
    let(:more_objects) { [object_1_1, object_1_2, object_1_1_1] }

    let(:pm2_user) { pm2.create_user('pm2_user') }
    let(:pm2_user_attr) { pm2.create_user_attribute('pm2_user_attr') }
    let(:pm2_operation_1) { pm2.create_operation('pm2_operation_1') }
    let(:pm2_operation_2) { pm2.create_operation('pm2_operation_2') }
    let(:pm3_user_attr) { pm3.create_user_attribute('pm3_user_attr') }

    # For specs that require more attribute differentiation for filtering
    let(:darken_colors) do
      ->{
        user_2.update(color: 'navy_blue')
        user_attr_2.update(color: 'forest_green')
        pm2_operation_2.update(color: 'crimson')
      }
    end

    before do
      user_attributes.each { |ua| pm1.add_assignment(user_1, ua) }
      pm1.add_assignment(user_attr_1, user_attr_2)
      pm1.add_assignment(opset_1, operation_1)
      pm1.add_assignment(user_2, user_attr_1)
      pm1.add_assignment(user_3, user_attr_1)

      object_attributes.product(user_attributes) { |oa, ua| pm1.add_association(ua, opset_1, oa) }
      object_attributes.zip(objects) { |oa, obj| pm1.add_assignment(obj, oa) }

      # Depth 1 connections from user_1 to the other policy machines
      pm1.add_link(user_1, pm2_user)
      pm1.add_link(user_1, pm2_operation_1)
      pm1.add_link(user_1, pm2_operation_2)
      pm1.add_link(user_1, pm2_user_attr)
      # Depth + connections from user_1 to the other policy machines
      pm2.add_link(pm2_operation_1, pm3_user_attr)
      pm2.add_link(pm2_operation_2, pm3_user_attr)

      # Users are blue, UAs are green, operations are red
      users.each { |user| user.update(color: 'blue') }
      pm2_user.update(color: 'blue')
      user_attributes.each { |ua| ua.update(color: 'green') }
      pm2_user_attr.update(color: 'green')
      pm3_user_attr.update(color: 'green')
      pm2_operation_1.update(color: 'red')
      pm2_operation_2.update(color: 'red')
    end

    describe '#descendants' do
      context 'no filter is applied' do
        # TODO normalize return value types
        it 'returns appropriate descendants' do
          expect(user_1.descendants).to match_array(user_attributes.map(&:stored_pe))
        end
      end

      context 'a filter is applied' do
        it 'applies a single filter if one is supplied' do
          green_descendants = user_1.descendants(color: 'green')
          expect(green_descendants).to match_array(user_attributes.map(&:stored_pe))
        end

        it 'applies multiple filters if they are supplied' do
          green_descendants = user_1.descendants(color: 'green', unique_identifier: 'user_attr_3')
          expect(green_descendants).to contain_exactly(user_attr_3.stored_pe)
        end

        it 'returns appropriate results when filters apply to no descendants' do
          expect(user_1.descendants(color: 'taupe')).to be_empty
          expect { user_1.descendants(not_a_real_attribute: 'fake') }.to raise_error(ArgumentError)
        end
      end
    end

    describe '#pluck_from_descendants' do
      before { darken_colors.call }

      context 'no filter is applied' do
        it 'returns appropriate descendants and the specified attribute' do
          plucked_results = [{ color: 'green' }, { color: 'forest_green' }, { color: 'green' }]
          expect(user_1.pluck_from_descendants(fields: [:color])).to match_array(plucked_results)
        end

        it 'returns appropriate descendants and multiple specified attributes' do
          plucked_results = [
            { unique_identifier: 'user_attr_1', color: 'green' },
            { unique_identifier: 'user_attr_2', color: 'forest_green' },
            { unique_identifier: 'user_attr_3', color: 'green' }]
          expect(user_1.pluck_from_descendants(fields: [:unique_identifier, :color])).to match_array(plucked_results)
        end

        it 'errors appropriately when nonexistent attributes are specified' do
          expect { expect(user_1.pluck_from_descendants(fields: ['favorite_mountain'])) }
            .to raise_error(ArgumentError)
        end

        it 'errors appropriately when no attributes are specified' do
          expect { expect(user_1.pluck_from_descendants(fields: [])) }.to raise_error(ArgumentError)
        end
      end

      context 'a filter is applied' do
        it 'applies a single filter if one is supplied' do
          plucked_results = [{ color: 'green' }, { color: 'green' }]
          expect(user_1.pluck_from_descendants(fields: [:color], filters: { color: 'green' }))
            .to match_array(plucked_results)
        end

        it 'applies multiple filters if they are supplied' do
          args = { fields: [:unique_identifier], filters: { unique_identifier: 'user_attr_1', color: 'green' } }
          expect(user_1.pluck_from_descendants(args)).to contain_exactly({ unique_identifier: 'user_attr_1' })
        end

        it 'returns appropriate results when filters apply to no descendants' do
          expect(user_1.pluck_from_descendants(fields: [:unique_identifier], filters: { color: 'red' })).to be_empty
        end
      end
    end

    describe '#link_descendants' do
      context 'no filter is applied' do
        it 'returns appropriate cross descendants one level deep' do
          expect(pm2_operation_1.link_descendants).to contain_exactly(pm3_user_attr.stored_pe)
        end

        it 'returns appropriate cross descendants multiple levels deep' do
          link_descendants = [pm2_user, pm2_operation_1, pm2_operation_2, pm2_user_attr, pm3_user_attr]
          expect(user_1.link_descendants).to match_array(link_descendants.map(&:stored_pe))
        end
      end

      context 'a filter is applied' do
        it 'applies a single filter if one is supplied' do
          link_descendants = [pm2_user_attr, pm3_user_attr]
          expect(user_1.link_descendants(color: 'green')).to match_array(link_descendants.map(&:stored_pe))
        end

        it 'applies multiple filters if they are supplied' do
          expect(user_1.link_descendants(color: 'green', unique_identifier: 'pm2_user_attr'))
            .to contain_exactly(pm2_user_attr.stored_pe)
        end

        it 'returns appropriate results when filters apply to no link_descendants' do
          expect(user_1.link_descendants(color: 'taupe')).to be_empty
          expect { user_1.link_descendants(not_a_real_attribute: 'fake') }.to raise_error(ArgumentError)
        end
      end
    end

    describe '#ancestors' do
      context 'no filter is applied' do
        it 'returns appropriate ancestors' do
          expect(user_attr_1.ancestors).to match_array(users.map(&:stored_pe))
        end
      end

      context 'a filter is applied' do
        it 'applies a single filter if one is supplied' do
          expect(user_attr_1.ancestors(color: 'blue')).to match_array(users.map(&:stored_pe))
        end

        it 'applies multiple filters if they are supplied' do
          expect(user_attr_1.ancestors(color: 'blue', unique_identifier: 'user_2')).to contain_exactly(user_2.stored_pe)
        end

        it 'returns appropriate results when filters apply to no ancestors' do
          expect(user_attr_1.ancestors(color: 'taupe')).to be_empty
          expect { user_attr_1.ancestors(not_a_real_attribute: 'fake') }.to raise_error(ArgumentError)
        end
      end
    end

    describe '#pluck_from_ancestors' do
      before { darken_colors.call }

      context 'no filter is applied' do
        it 'returns appropriate ancestors and the specified attribute' do
          plucked_results = [{ color: 'blue' }, { color: 'navy_blue' }, { color: 'blue' }]
          expect(user_attr_1.pluck_from_ancestors(fields: [:color])).to match_array(plucked_results)
        end

        it 'returns appropriate ancestors and multiple specified attributes' do
          plucked_results = [
            { unique_identifier: 'user_1', color: 'blue' },
            { unique_identifier: 'user_2', color: 'navy_blue' },
            { unique_identifier: 'user_3', color: 'blue' }]
          expect(user_attr_1.pluck_from_ancestors(fields: [:unique_identifier, :color])).to match_array(plucked_results)
        end

        it 'errors appropriately when nonexistent attributes are specified' do
          expect { expect(user_attr_1.pluck_from_ancestors(fields: ['favorite_mountain'])) }
            .to raise_error(ArgumentError)
        end

        it 'errors appropriately when no attributes are specified' do
          expect { expect(user_attr_1.pluck_from_ancestors(fields: [])) }.to raise_error(ArgumentError)
        end
      end

      context 'a filter is applied' do
        it 'applies a single filter if one is supplied' do
          plucked_results = [{ color: 'blue' }, { color: 'blue' }]
          expect(user_attr_1.pluck_from_ancestors(fields: [:color], filters: { color: 'blue' }))
            .to match_array(plucked_results)
        end

        it 'applies multiple filters if they are supplied' do
          args = { fields: [:unique_identifier], filters: { unique_identifier: 'user_1', color: 'blue' } }
          expect(user_attr_1.pluck_from_ancestors(args)).to contain_exactly(unique_identifier: 'user_1')
        end

        it 'returns appropriate results when filters apply to no ancestors' do
          expect(user_attr_1.pluck_from_ancestors(fields: [:unique_identifier], filters: { color: 'red' })).to be_empty
        end
      end
    end

    describe '#pluck_ancestor_tree' do
      let(:user_attr_4) { pm1.create_user_attribute('user_attr_4') }
      let(:user_attr_5) { pm1.create_user_attribute('user_attr_5') }
      let(:user_attr_6) { pm1.create_user_attribute('user_attr_6') }
      let!(:single_ancestors) { [user_attr_4, user_attr_5, user_attr_6] }

      let(:user_attr_7) { pm1.create_user_attribute('user_attr_7') }
      let(:user_attr_8) { pm1.create_user_attribute('user_attr_8') }
      let(:user_attr_9) { pm1.create_user_attribute('user_attr_9') }
      let!(:double_ancestors) { [user_attr_7, user_attr_8, user_attr_9] }

      let(:user_attr_10) { pm1.create_user_attribute('user_attr_10') }

      before do
        darken_colors.call

        single_ancestors.each { |ancestor| ancestor.update(color: 'gold' ) }
        double_ancestors.each { |ancestor| ancestor.update(color: 'silver' ) }
        pm1.add_assignment(user_attr_4, user_attr_1)
        pm1.add_assignment(user_attr_5, user_attr_1)
        pm1.add_assignment(user_attr_6, user_attr_1)

        pm1.add_assignment(user_attr_7, user_attr_4)
        pm1.add_assignment(user_attr_8, user_attr_5)
        pm1.add_assignment(user_attr_9, user_attr_6)
      end

      context 'no filter is applied' do
        it 'returns appropriate ancestors and the specified attribute' do
          plucked_results = HashWithIndifferentAccess.new(
            user_1: [],
            user_2: [],
            user_3: [],
            user_attr_4: [{ unique_identifier: 'user_attr_7' }],
            user_attr_5: [{ unique_identifier: 'user_attr_8' }],
            user_attr_6: [{ unique_identifier: 'user_attr_9' }],
            user_attr_7: [],
            user_attr_8: [],
            user_attr_9: []
          )

          expect(user_attr_1.pluck_ancestor_tree(fields: [:unique_identifier])).to eq(plucked_results)
        end

        it 'returns appropriate ancestors and multiple specified attributes' do
          plucked_results = HashWithIndifferentAccess.new(
            user_1: [],
            user_2: [],
            user_3: [],
            user_attr_4: [{ unique_identifier: 'user_attr_7', color: 'silver' }],
            user_attr_5: [{ unique_identifier: 'user_attr_8', color: 'silver' }],
            user_attr_6: [{ unique_identifier: 'user_attr_9', color: 'silver' }],
            user_attr_7: [],
            user_attr_8: [],
            user_attr_9: []
          )
          expect(user_attr_1.pluck_ancestor_tree(fields: [:unique_identifier, :color])).to eq(plucked_results)
        end

        it 'errors appropriately when nonexistent attributes are specified' do
          expect { user_attr_1.pluck_ancestor_tree(fields: [:dog]) }.to raise_error(ArgumentError)
        end

        it 'errors appropriately when no attributes are specified' do
          expect { user_attr_1.pluck_ancestor_tree(fields: []) }.to raise_error(ArgumentError)
        end
      end

      context 'a filter is applied' do
        it 'applies a single filter if one is supplied' do
          plucked_results = HashWithIndifferentAccess.new(user_attr_7: [], user_attr_8: [], user_attr_9: [])
          params = { fields: [:unique_identifier], filters: { color: 'silver'} }
          expect(user_attr_1.pluck_ancestor_tree(params)).to eq(plucked_results)
        end

        it 'applies multiple filters if they are supplied' do
          plucked_results = HashWithIndifferentAccess.new('user_attr_9': [])
          params = { fields: [:unique_identifier], filters: { color: 'silver', unique_identifier: 'user_attr_9' } }
          expect(user_attr_1.pluck_ancestor_tree(params)).to eq(plucked_results)
        end

        it 'returns appropriate results when filters apply to ancestors that have no ancestors themselves' do
          user_attr_10.update(color: 'indigo')
          pm1.add_assignment(user_attr_10, user_attr_1)

          plucked_results = HashWithIndifferentAccess.new(user_attr_10: [])
          params = { fields: [:unique_identifier], filters: { color: 'indigo'} }
          expect(user_attr_1.pluck_ancestor_tree(params)).to eq(plucked_results)
        end

        it 'returns appropriate results when filters apply to ancestors but not their ancestors' do
          plucked_results = HashWithIndifferentAccess.new(user_attr_4: [], user_attr_5: [], user_attr_6: [])
          params = { fields: [:unique_identifier], filters: { color: 'gold'} }
          expect(user_attr_1.pluck_ancestor_tree(params)).to eq(plucked_results)
        end

        it 'returns appropriate results when filters apply to no ancestors' do
          params = { fields: [:unique_identifier], filters: { color: 'obsidian'} }
          expect(user_attr_1.pluck_ancestor_tree(params)).to match_array({})
        end
      end
    end

    describe '#link_ancestors' do
      context 'no filter is applied' do
        it 'returns appropriate cross ancestors one level deep' do
          expect(pm2_user.link_ancestors).to contain_exactly(user_1.stored_pe)
        end

        it 'returns appropriate cross ancestors multiple levels deep' do
          link_ancestors = [pm2_operation_1, pm2_operation_2, user_1]
          expect(pm3_user_attr.link_ancestors).to match_array(link_ancestors.map(&:stored_pe))
        end
      end

      context 'a filter is applied' do
        it 'applies a single filter if one is supplied' do
          expect(pm3_user_attr.link_ancestors(color: 'blue')).to contain_exactly(user_1.stored_pe)
        end

        it 'applies multiple filters if they are supplied' do
          expect(pm3_user_attr.link_ancestors(color: 'red', unique_identifier: 'pm2_operation_1'))
            .to contain_exactly(pm2_operation_1.stored_pe)
        end

        it 'returns appropriate results when filters apply to no link_ancestors' do
          expect(pm3_user_attr.link_ancestors(color: 'taupe')).to be_empty
          expect { pm3_user_attr.link_ancestors(not_a_real_attribute: 'fake') }.to raise_error(ArgumentError)
        end
      end
    end

    describe '#parents' do
      context 'no filter is applied' do
        it 'returns appropriate parents' do
          expect(user_attr_2.parents).to contain_exactly(user_attr_1.stored_pe, user_1.stored_pe)
        end
      end

      context 'a filter is applied' do
        it 'applies a single filter if one is supplied' do
          expect(user_attr_1.parents(color: 'blue')).to match_array(users.map(&:stored_pe))
        end

        it 'applies multiple filters if they are supplied' do
          expect(user_attr_1.parents(color: 'blue', unique_identifier: 'user_3')).to contain_exactly(user_3.stored_pe)
        end

        it 'returns appropriate results when filters apply to no parents' do
          expect(user_attr_1.parents(color: 'taupe')).to be_empty
          expect { user_attr_1.parents(not_a_real_attribute: 'fake') }.to raise_error(ArgumentError)
        end
      end
    end

    describe '#pluck_from_parents' do
      before { darken_colors.call }

      context 'no filter is applied' do
        it 'returns appropriate parents and the specified attribute' do
          plucked_results = [{ color: 'blue' }, { color: 'navy_blue' }, { color: 'blue' }]
          expect(user_attr_1.pluck_from_parents(fields: [:color])).to match_array(plucked_results)
        end

        it 'returns appropriate parents and multiple specified attributes' do
          plucked_results = [
            { unique_identifier: 'user_1', color: 'blue' },
            { unique_identifier: 'user_2', color: 'navy_blue' },
            { unique_identifier: 'user_3', color: 'blue' }]
          expect(user_attr_1.pluck_from_parents(fields: [:unique_identifier, :color])).to match_array(plucked_results)
        end

        it 'errors appropriately when nonexistent attributes are specified' do
          expect { expect(user_attr_1.pluck_from_parents(fields: ['favorite_mountain'])) }
            .to raise_error(ArgumentError)
        end

        it 'errors appropriately when no attributes are specified' do
          expect { expect(user_attr_1.pluck_from_parents(fields: [])) }.to raise_error(ArgumentError)
        end
      end

      context 'a filter is applied' do
        it 'applies a single filter if one is supplied' do
          plucked_results = [{ color: 'blue' }, { color: 'blue' }]
          expect(user_attr_1.pluck_from_parents(fields: [:color], filters: { color: 'blue' }))
            .to match_array(plucked_results)
        end

        it 'applies multiple filters if they are supplied' do
          args = { fields: [:unique_identifier], filters: { unique_identifier: 'user_1', color: 'blue' } }
          expect(user_attr_1.pluck_from_parents(args)).to contain_exactly({ unique_identifier: 'user_1' })
        end

        it 'returns appropriate results when filters apply to no parents' do
          expect(user_attr_1.pluck_from_parents(fields: [:unique_identifier], filters: { color: 'red' })).to be_empty
        end
      end
    end

    describe '#children' do
      context 'no filter is applied' do
        it 'returns appropriate children' do
          expect(user_attr_1.children).to contain_exactly(user_attr_2.stored_pe)
        end
      end

      context 'a filter is applied' do
        it 'applies a single filter if one is supplied' do
          expect(user_1.children(color: 'green')).to match_array(user_attributes.map(&:stored_pe))
        end

        it 'applies multiple filters if they are supplied' do
          expect(user_1.children(color: 'green', unique_identifier: 'user_attr_2')).to contain_exactly(user_attr_2.stored_pe)
        end

        it 'returns appropriate results when filters apply to no children' do
          expect(user_1.children(color: 'taupe')).to be_empty
          expect { user_1.children(not_a_real_attribute: 'fake') }.to raise_error(ArgumentError)
        end
      end
    end

    describe '#pluck_from_children' do
      before { darken_colors.call }

      context 'no filter is applied' do
        it 'returns appropriate children and the specified attribute' do
          plucked_results = [{ color: 'green' }, { color: 'forest_green' }, { color: 'green' }]
          expect(user_1.pluck_from_children(fields: [:color])).to match_array(plucked_results)
        end

        it 'returns appropriate children and multiple specified attributes' do
          plucked_results = [
            { unique_identifier: 'user_attr_1', color: 'green' },
            { unique_identifier: 'user_attr_2', color: 'forest_green' },
            { unique_identifier: 'user_attr_3', color: 'green' }]
          expect(user_1.pluck_from_children(fields: [:unique_identifier, :color])).to match_array(plucked_results)
        end

        it 'errors appropriately when nonexistent attributes are specified' do
          expect { expect(user_1.pluck_from_children(fields: ['favorite_mountain'])) }
            .to raise_error(ArgumentError)
        end

        it 'errors appropriately when no attributes are specified' do
          expect { expect(user_1.pluck_from_children(fields: [])) }.to raise_error(ArgumentError)
        end
      end

      context 'a filter is applied' do
        it 'applies a single filter if one is supplied' do
          plucked_results = [{ color: 'green' }, { color: 'green' }]
          expect(user_1.pluck_from_children(fields: [:color], filters: { color: 'green' }))
            .to match_array(plucked_results)
        end

        it 'applies multiple filters if they are supplied' do
          args = { fields: [:unique_identifier], filters: { unique_identifier: 'user_attr_1', color: 'green' } }
          expect(user_1.pluck_from_children(args)).to contain_exactly({ unique_identifier: 'user_attr_1' })
        end

        it 'returns appropriate results when filters apply to no children' do
          expect(user_1.pluck_from_children(fields: [:unique_identifier], filters: { color: 'red' })).to be_empty
        end
      end
    end

    describe '#link_parents' do
      context 'no filter is applied' do
        it 'returns appropriate parents' do
          link_parents = [pm2_operation_1, pm2_operation_2]
          expect(pm3_user_attr.link_parents).to match_array(link_parents.map(&:stored_pe))
        end
      end

      context 'a filter is applied' do
        it 'applies a single filter if one is supplied' do
          red_link_parents = [pm2_operation_1, pm2_operation_2]
          expect(pm3_user_attr.link_parents(color: 'red')).to match_array(red_link_parents.map(&:stored_pe))
        end

        it 'applies multiple filters if they are supplied' do
          expect(pm3_user_attr.link_parents(color: 'red', unique_identifier: 'pm2_operation_2'))
            .to contain_exactly(pm2_operation_2.stored_pe)
        end

        it 'returns appropriate results when filters apply to no link_parents' do
          expect(pm3_user_attr.link_parents(color: 'taupe')).to be_empty
          expect { pm3_user_attr.link_parents(not_a_real_attribute: 'fake') }.to raise_error(ArgumentError)
        end
      end
    end

    describe '#pluck_from_link_parents' do
      before { darken_colors.call }

      context 'no filter is applied' do
        it 'returns appropriate link_parents and the specified attribute' do
          plucked_results = [{ color: 'red' }, { color: 'crimson' }]
          expect(pm3_user_attr.pluck_from_link_parents(fields: [:color])).to match_array(plucked_results)
        end

        it 'returns appropriate link_parents and multiple specified attributes' do
          plucked_results = [
            { unique_identifier: 'pm2_operation_1', color: 'red' },
            { unique_identifier: 'pm2_operation_2', color: 'crimson' }]
          expect(pm3_user_attr.pluck_from_link_parents(fields: [:unique_identifier, :color])).to match_array(plucked_results)
        end

        it 'errors appropriately when nonexistent attributes are specified' do
          expect { expect(pm3_user_attr.pluck_from_link_parents(fields: ['favorite_mountain'])) }
            .to raise_error(ArgumentError)
        end

        it 'errors appropriately when no attributes are specified' do
          expect { expect(pm3_user_attr.pluck_from_link_parents(fields: [])) }.to raise_error(ArgumentError)
        end
      end

      context 'a filter is applied' do
        it 'applies a single filter if one is supplied' do
          plucked_results = [{ color: 'red' }]
          expect(pm3_user_attr.pluck_from_link_parents(fields: [:color], filters: { color: 'red' }))
            .to match_array(plucked_results)
        end

        it 'applies multiple filters if they are supplied' do
          args = { fields: [:unique_identifier], filters: { unique_identifier: 'pm2_operation_1', color: 'red' } }
          expect(pm3_user_attr.pluck_from_link_parents(args)).to contain_exactly({ unique_identifier: 'pm2_operation_1' })
        end

        it 'returns appropriate results when filters apply to no link_parents' do
          expect(pm3_user_attr.pluck_from_link_parents(fields: [:unique_identifier], filters: { color: 'blue' })).to be_empty
        end
      end
    end

    describe '#link_children' do
      context 'no filter is applied' do
        it 'returns appropriate children' do
          link_children = [pm2_user, pm2_operation_1, pm2_operation_2, pm2_user_attr]
          expect(user_1.link_children).to match_array(link_children.map(&:stored_pe))
        end
      end

      context 'a filter is applied' do
        it 'applies a single filter if one is supplied' do
          green_link_children = [pm2_user_attr]
          expect(user_1.link_children(color: 'green')).to match_array(green_link_children.map(&:stored_pe))
        end

        it 'applies multiple filters if they are supplied' do
          expect(user_1.link_children(color: 'red', unique_identifier: 'pm2_operation_1'))
            .to contain_exactly(pm2_operation_1.stored_pe)
        end

        it 'returns appropriate results when filters apply to no link_children' do
          expect(user_1.link_children(color: 'taupe')).to be_empty
          expect { user_1.link_children(not_a_real_attribute: 'fake') }.to raise_error(ArgumentError)
        end
      end
    end

    describe '#pluck_from_link_children' do
      before { darken_colors.call }

      context 'no filter is applied' do
        it 'returns appropriate link_children and the specified attribute' do
          plucked_results = [{ color: 'blue' }, { color: 'red' }, { color: 'crimson' }, { color: 'green' }]
          expect(user_1.pluck_from_link_children(fields: [:color])).to match_array(plucked_results)
        end

        it 'returns appropriate link_children and multiple specified attributes' do
          plucked_results = [
            { unique_identifier: 'pm2_user', color: 'blue' },
            { unique_identifier: 'pm2_operation_1', color: 'red' },
            { unique_identifier: 'pm2_operation_2', color: 'crimson' },
            { unique_identifier: 'pm2_user_attr', color: 'green' }]
          expect(user_1.pluck_from_link_children(fields: [:unique_identifier, :color])).to match_array(plucked_results)
        end

        it 'errors appropriately when nonexistent attributes are specified' do
          expect { expect(user_1.pluck_from_link_children(fields: ['favorite_mountain'])) }
            .to raise_error(ArgumentError)
        end

        it 'errors appropriately when no attributes are specified' do
          expect { expect(user_1.pluck_from_link_children(fields: [])) }.to raise_error(ArgumentError)
        end
      end

      context 'a filter is applied' do
        it 'applies a single filter if one is supplied' do
          plucked_results = [{ color: 'green' }]
          expect(user_1.pluck_from_link_children(fields: [:color], filters: { color: 'green' }))
            .to match_array(plucked_results)
        end

        it 'applies multiple filters if they are supplied' do
          args = { fields: [:unique_identifier], filters: { unique_identifier: 'pm2_user', color: 'blue' } }
          expect(user_1.pluck_from_link_children(args)).to contain_exactly({ unique_identifier: 'pm2_user' })
        end

        it 'returns appropriate results when filters apply to no link_children' do
          expect(user_1.pluck_from_link_children(fields: [:unique_identifier], filters: { color: 'chartreuse' })).to be_empty
        end
      end
    end

    describe 'accessible_objects' do
      before do
        more_object_attributes.zip(more_objects) { |oa, obj| pm1.add_assignment(obj, oa) }
        pm1.add_assignment(object_attr_1_1, object_attr_1)
        pm1.add_assignment(object_attr_1_2, object_attr_1)
        pm1.add_assignment(object_attr_1_1_1, object_attr_1_1)
      end
      it 'whatever' do
        accessible_objects = (objects + more_objects).map(&:stored_pe)
        expect(pm1.accessible_objects(user_1, operation_1)).to match_array(accessible_objects)
      end

      it 'with scope now' do
        accessible_objects = ([object_1] + more_objects).map(&:stored_pe)
        expect(pm1.accessible_objects(user_1, operation_1, accessible_scope: object_attr_1)).to match_array(accessible_objects)
      end
    end
  end

  describe 'PolicyMachine integration with PolicyMachineStorageAdapter::ActiveRecord' do
    it_behaves_like 'a policy machine' do
      let(:policy_machine) do
        PolicyMachine.new(name: 'ActiveRecord PM', storage_adapter: PolicyMachineStorageAdapter::ActiveRecord)
      end

      #TODO: move to shared example group when in memory equivalent exists
      describe '.serialize' do
        before(:all) do
          klass = PolicyMachineStorageAdapter::ActiveRecord::PolicyElement
          klass.serialize(store: :document, name: :is_arbitrary, serializer: JSON)
        end

        (PolicyMachine::POLICY_ELEMENT_TYPES).each do |type|
          describe 'store' do
            it 'can specify a root store level store supported by the backing system' do
              some_hash = { 'foo' => 'bar' }
              obj = policy_machine.send("create_#{type}", SecureRandom.uuid, { document: some_hash })

              expect(obj.stored_pe.document).to eq some_hash
              expect(obj.stored_pe.extra_attributes).to be_empty
            end

            it 'can specify additional key names to be serialized' do
              pm2_hash = { 'is_arbitrary' => ['thing'] }
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
