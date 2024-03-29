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

    describe 'scoping privileges by user attribute' do
      let(:priv_pm) do
        PolicyMachine.new(name: 'Privilege Scoping PM', storage_adapter: PolicyMachineStorageAdapter::ActiveRecord)
      end

      let(:user_1) { priv_pm.create_user('user_1') }
      let(:color_1) { priv_pm.create_user_attribute('color_1', color: 'pink') }
      let(:color_2) { priv_pm.create_user_attribute('color_2', color: 'purple') }
      let(:color_3) { priv_pm.create_user_attribute('color_3', color: 'green') }

      let(:object_1) { priv_pm.create_object('object_1') }
      let(:object_2) { priv_pm.create_object('object_2') }
      let(:object_3) { priv_pm.create_object('object_3') }
      let(:object_4) { priv_pm.create_object('object_4') }
      let(:oa_1) { priv_pm.create_object_attribute('oa_1') }

      let(:object_5) { priv_pm.create_object('object_5') }
      let(:object_6) { priv_pm.create_object('object_6') }
      let(:oa_2) { priv_pm.create_object_attribute('oa_2') }

      let(:object_7) { priv_pm.create_object('object_7') }
      let(:oa_3) { priv_pm.create_object_attribute('oa_3') }

      let(:oa_4) { priv_pm.create_object_attribute('oa_4') }
      let(:oa_5) { priv_pm.create_object_attribute('oa_5') }

      let(:painter) { priv_pm.create_operation_set('painter') }
      let(:paint) { priv_pm.create_operation('paint') }
      let(:creator) { priv_pm.create_operation_set('creator') }
      let(:create) { priv_pm.create_operation('create') }

      before do
        priv_pm.add_assignment(user_1, color_2)
        priv_pm.add_assignment(user_1, color_3)
        priv_pm.add_assignment(user_1, color_1)

        priv_pm.add_assignment(creator, painter)

        priv_pm.add_assignment(object_1, oa_1)
        priv_pm.add_assignment(object_2, oa_1)
        priv_pm.add_assignment(object_3, object_2)
        priv_pm.add_assignment(object_4, object_2)
        priv_pm.add_assignment(object_5, oa_2)
        priv_pm.add_assignment(object_6, oa_2)

        priv_pm.add_assignment(object_7, oa_3)

        priv_pm.add_assignment(oa_1, oa_4)
        priv_pm.add_assignment(oa_2, oa_4)

        priv_pm.add_assignment(oa_4, oa_5)
        priv_pm.add_assignment(oa_3, oa_5)

        priv_pm.add_assignment(creator, create)
        priv_pm.add_assignment(painter, paint)

        priv_pm.add_association(color_1, painter, oa_4)
        priv_pm.add_association(color_2, creator, oa_2)
        priv_pm.add_association(color_3, creator, oa_1)
      end

      describe 'is_privilege_with_filters?' do
        context 'when the user has access via a filtered user attribute' do
          it 'returns true' do
            filters = { user_attributes: { color: 'purple' } }

            expect(
              priv_pm.is_privilege_with_filters?(user_1, create, object_5, filters: filters)
            ).to be true
          end

          context 'and a prohibition is set' do
            let(:cant_create) { priv_pm.create_operation_set('cant_create') }

            before do
              priv_pm.add_assignment(cant_create, create.prohibition)
              priv_pm.add_association(color_2, cant_create, object_5)
            end

            it 'returns false' do
              filters = { user_attributes: { color: 'purple' } }

              expect(
                priv_pm.is_privilege_with_filters?(user_1, create, object_5, filters: filters)
              ).to be false
            end
          end
        end

        context 'when the user has access via cascading operation sets assigned to the user attribute' do
          let(:object_7_handling) { priv_pm.create_operation_set('object_7_handling') }

          before do
            priv_pm.add_assignment(object_7_handling, creator)
            priv_pm.add_association(color_2, object_7_handling, oa_3)
          end

          it 'returns true' do
            filters = { user_attributes: { color: 'purple' } }

            expect(
              priv_pm.is_privilege_with_filters?(user_1, create, object_7, filters: filters)
            ).to be true
          end
        end

        # Support for cascading user attribute assignments is not yet supported
        context 'when the user has access via cascading user attributes' do
          let(:object_7_handler) { priv_pm.create_user_attribute('object_7_handler') }

          before do
            priv_pm.add_assignment(object_7_handler, color_2)
            priv_pm.add_association(object_7_handler, creator, object_7)
          end

          it 'returns false' do
            filters = { user_attributes: { color: 'purple' } }

            expect(
              priv_pm.is_privilege_with_filters?(user_1, create, object_7, filters: filters)
            ).to be false
          end
        end

        context 'when the user has access via a user attribute that is filtered out' do
          it 'returns false' do
            filters = { user_attributes: { color: 'pink' } }

            expect(
              priv_pm.is_privilege_with_filters?(user_1, create, object_5, filters: filters)
            ).to be false
          end
        end

        context 'when the user does not have access via any user attribute' do
          it 'returns false' do
            filters = { user_attributes: { color: 'purple' } }

            expect(
              priv_pm.is_privilege_with_filters?(user_1, create, object_7, filters: filters)
            ).to be false
          end
        end
      end

      describe 'scoped_privileges' do
        context 'when the user has access via a filtered user attribute' do
          it 'returns all the privileges granted by that attribute' do
            filters = { user_attributes: { color: 'purple' } }

            expect(
              priv_pm.scoped_privileges(user_1, object_5, filters: filters)
            ).to contain_exactly([user_1, create, object_5], [user_1, paint, object_5])
          end

          context 'when there is a prohibition' do
            let(:cant_create) { priv_pm.create_operation_set('cant_create') }

            before do
              priv_pm.add_assignment(cant_create, create.prohibition)
              priv_pm.add_association(color_1, cant_create, object_5)
            end

            it 'does not return the prohibited privilege' do
              filters = { user_attributes: { color: 'purple' } }

              expect(
                priv_pm.scoped_privileges(user_1, object_5, filters: filters)
              ).to contain_exactly([user_1, paint, object_5])
            end
          end
        end

        context 'when the user has access via a user attribute that is filtered out' do
          it 'does not return the privilege given by the other user attribute' do
            filters = { user_attributes: { color: 'pink' } }

            expect(
              priv_pm.scoped_privileges(user_1, object_5, filters: filters)
            ).to match_array([[user_1, paint, object_5]])
          end
        end

        context 'when the user does not have access via any user attribute' do
          it 'returns an empty array' do
            filters = { user_attributes: { color: 'purple' } }

            expect(
              priv_pm.scoped_privileges(user_1, object_7, filters: filters)
            ).to be_empty
          end
        end
      end

      describe 'is_privilege_ignoring_prohibitions?' do
        let(:cant_create) { priv_pm.create_operation_set('cant_create') }

        before do
          priv_pm.add_assignment(cant_create, create.prohibition)
          priv_pm.add_association(color_2, cant_create, object_5)
        end

        context 'when a filter is passed' do
          it 'calls is_privilege_with_filters?' do
            expect(priv_pm.policy_machine_storage_adapter).to receive(:is_privilege_with_filters?)

            filters = { user_attributes: { color: 'purple' } }
            priv_pm.is_privilege_ignoring_prohibitions?(user_1, create, object_5, filters: filters)
          end

          it 'ignores prohibitions' do
            filters = { user_attributes: { color: 'purple' } }

            expect(
              priv_pm.is_privilege_ignoring_prohibitions?(user_1, create, object_5, filters: filters)
            ).to be true
          end
        end
      end

      describe 'accessible_objects' do
        before do
          allow_any_instance_of(PolicyMachineStorageAdapter::ActiveRecord)
            .to receive(:use_accessible_objects_function?)
            .and_return(false)
        end

        it 'returns objects accessible via the filtered attribute' do
          filters = { user_attributes: { color: 'purple' } }

          expect(
            priv_pm.accessible_objects(
              user_1,
              create,
              filters: filters,
              key: :unique_identifier
            ).map(&:unique_identifier)
          ).to match_array(['object_5', 'object_6'])
        end

        it 'does not return objects that are not accessible via the filtered attribute' do
          filters = { user_attributes: { color: 'pink' } }

          expect(
            priv_pm.accessible_objects(user_1, create, filters: filters)
          ).to be_empty
        end

        it 'does not use a PostgreSQL function' do
          expect_any_instance_of(PolicyMachineStorageAdapter::ActiveRecord)
            .not_to receive(:accessible_objects_function)

          priv_pm.accessible_objects(
            user_1,
            create,
            direct_only: true,
            ignore_prohibitions: true,
            fields: [:id])
        end

        context 'prohibitions' do
          let(:cant_create) { priv_pm.create_operation_set('cant_create') }

          before do
            priv_pm.add_assignment(cant_create, create.prohibition)
            priv_pm.add_association(color_2, cant_create, object_5)
          end

          it 'does not return objects with prohibitions' do
            filters = { user_attributes: { color: 'purple' } }

            expect(
              priv_pm.accessible_objects(
                user_1,
                create,
                filters: filters,
                key: :unique_identifier
              ).map(&:unique_identifier)
            ).to_not include('object_5')
          end
        end

        context 'direct only' do
          before { priv_pm.add_association(color_1, creator, object_7) }

          it 'only considers associations that go directly to objects' do
            expect(priv_pm.accessible_objects(
                user_1,
                create,
                direct_only: true
              ).map(&:unique_identifier)
            ).to contain_exactly('object_7')
          end

          it 'returns an array' do
            expect(priv_pm.accessible_objects(
              user_1,
              create,
              direct_only: true
            ).class).to eq(Array)
          end
        end

        context 'includes' do
          it 'returns only objects that match' do
            expect(
              priv_pm.accessible_objects(
                user_1,
                create,
                key: :unique_identifier,
                includes: '4'
              ).map(&:unique_identifier)
            ).to eq(['object_4'])
          end
        end

        context 'fields' do
          it 'plucks only requested fields' do
            expect(
              priv_pm.accessible_objects(
                user_1,
                create,
                fields: [:unique_identifier, :policy_machine_uuid]
              )
            ).to match_array([
              {
                unique_identifier: object_1.unique_identifier,
                policy_machine_uuid: priv_pm.uuid
              },
              {
                unique_identifier: object_2.unique_identifier,
                policy_machine_uuid: priv_pm.uuid
              },
              {
                unique_identifier: object_3.unique_identifier,
                policy_machine_uuid: priv_pm.uuid
              },
              {
                unique_identifier: object_4.unique_identifier,
                policy_machine_uuid: priv_pm.uuid
              },
              {
                unique_identifier: object_5.unique_identifier,
                policy_machine_uuid: priv_pm.uuid
              },
              {
                unique_identifier: object_6.unique_identifier,
                policy_machine_uuid: priv_pm.uuid
              }
            ])
          end

          it 'plucks a single field' do
            expect(
              priv_pm.accessible_objects(
                user_1,
                create,
                fields: [:unique_identifier]
              )
            ).to match_array([
              { unique_identifier: object_1.unique_identifier },
              { unique_identifier: object_2.unique_identifier },
              { unique_identifier: object_3.unique_identifier },
              { unique_identifier: object_4.unique_identifier },
              { unique_identifier: object_5.unique_identifier },
              { unique_identifier: object_6.unique_identifier }
            ])
          end
        end
      end

      describe 'accessible_objects_function' do
        context 'direct only' do
          before { priv_pm.add_association(color_1, creator, object_7) }

          it 'only considers associations that go directly to objects' do
            expect(priv_pm.accessible_objects(
                user_1,
                create,
                direct_only: true,
                ignore_prohibitions: true,
                fields: [:unique_identifier]
              )
            ).to contain_exactly('object_7')
          end

          it 'returns an array' do
            expect(priv_pm.accessible_objects(
              user_1,
              create,
              direct_only: true,
              ignore_prohibitions: true,
              fields: [:unique_identifier]
            ).class).to eq(Array)
          end

          it 'uses a PostgreSQL function' do
            expect_any_instance_of(PolicyMachineStorageAdapter::ActiveRecord)
              .to receive(:accessible_objects_function)

            priv_pm.accessible_objects(
              user_1,
              create,
              direct_only: true,
              ignore_prohibitions: true,
              fields: [:unique_identifier]
            )
          end
        end

        context 'not direct only' do
          it 'it is not called' do
            expect_any_instance_of(PolicyMachineStorageAdapter::ActiveRecord)
              .not_to receive(:accessible_objects_function)
            priv_pm.accessible_objects(user_1, create)
          end
        end
      end

      describe 'all_operations_for_user_or_attr_and_objs_or_attrs' do
        let(:color_4) { priv_pm.create_user_attribute('color_4', color: 'blue') }
        let(:sketcher) { priv_pm.create_operation_set('sketcher') }
        let(:sketch) { priv_pm.create_operation('sketch') }

        before do
          priv_pm.add_assignment(user_1, color_4)
          priv_pm.add_assignment(sketcher, sketch)
          priv_pm.add_association(color_4, sketcher, object_7)
        end

        context 'single association' do
          it 'returns operations for the given object_attribute_id' do
            result = priv_pm.all_operations_for_user_or_attr_and_objs_or_attrs(
              user_1,
              [object_7.id]
            )
            expect(result).to eq({ object_7.id => [sketch.to_s] })
          end
        end

        context 'multiple associations' do
          before do
            priv_pm.add_association(color_3, painter, object_7)
          end

          it 'returns operations for the given object_attribute_id' do
            priv_pm.add_association(color_3, painter, object_7)

            result = priv_pm.all_operations_for_user_or_attr_and_objs_or_attrs(
              user_1,
              [object_7.id]
            )
            expect(result.keys).to contain_exactly(object_7.id)
            expect(result[object_7.id]).to contain_exactly(paint.to_s, sketch.to_s)
          end

          it 'returns operations for multiple object_attribute_ids' do
            result = priv_pm.all_operations_for_user_or_attr_and_objs_or_attrs(
              user_1,
              [oa_1.id, object_7.id]
            )
            expect(result.keys).to contain_exactly(oa_1.id, object_7.id)
            expect(result[oa_1.id]).to contain_exactly(create.to_s, paint.to_s)
            expect(result[object_7.id]).to contain_exactly(sketch.to_s, paint.to_s)
          end

          context 'prohibitions' do
            let(:cant_paint) { priv_pm.create_operation_set('cant_paint') }

            before do
              priv_pm.add_assignment(cant_paint, paint.prohibition)
              priv_pm.add_association(color_3, cant_paint, object_7)
            end

            it 'returns prohibited operations' do
              result = priv_pm.all_operations_for_user_or_attr_and_objs_or_attrs(
                user_1,
                [object_7.id],
              )
              expect(result.keys).to contain_exactly(object_7.id)
              expect(result[object_7.id]).to contain_exactly(sketch.to_s, paint.to_s, paint.prohibition.to_s)
            end
          end

          context 'filters' do
            let(:filters) { { user_attributes: { color: color_3.color } } }

            it 'they work' do
              result = priv_pm.all_operations_for_user_or_attr_and_objs_or_attrs(
                user_1,
                [object_7.id],
                filters: filters
              )
              expect(result.keys).to contain_exactly(object_7.id)
              expect(result[object_7.id]).to contain_exactly(paint.to_s)
            end
          end
        end
      end

      describe 'accessible_objects_for_operations' do
        before do
          allow_any_instance_of(PolicyMachineStorageAdapter::ActiveRecord)
            .to receive(:use_accessible_objects_function?)
            .and_return(false)
        end

        it 'does not use a PostgreSQL function' do
          expect_any_instance_of(PolicyMachineStorageAdapter::ActiveRecord)
            .not_to receive(:accessible_objects_for_operations_function)

          result = priv_pm.accessible_objects_for_operations(
            user_1,
            [create, paint],
            direct_only: true,
            ignore_prohibitions: true,
            fields: [:id]
          )
        end

        context 'direct only' do
          context 'when there are directly accessible objects' do
            before do
              priv_pm.add_association(color_1, creator, object_6)
              priv_pm.add_association(color_2, creator, object_7)
            end

            it 'returns objects accessible via each of multiple given operations' do
              result = priv_pm.accessible_objects_for_operations(
                user_1,
                [create, paint],
                direct_only: true
              )
              # expected:
              # {
              #   'create' => [object_6.stored_pe, object_7.stored_pe],
              #   'paint' => [object_6.stored_pe, object_7.stored_pe],
              # }
              expect(result.keys).to contain_exactly(create.to_s, paint.to_s)
              expect(result[create.to_s]).to contain_exactly(object_6.stored_pe, object_7.stored_pe)
              expect(result[paint.to_s]).to contain_exactly(object_6.stored_pe, object_7.stored_pe)
            end

            it 'can handle string operations' do
              result = priv_pm.accessible_objects_for_operations(
                user_1,
                ['create', 'paint'],
                direct_only: true
              )
              # expected:
              # {
              #   'create' => [object_6.stored_pe, object_7.stored_pe],
              #   'paint' => [object_6.stored_pe, object_7.stored_pe],
              # }
              expect(result.keys).to contain_exactly('create', 'paint')
              expect(result['create']).to contain_exactly(object_6.stored_pe, object_7.stored_pe)
              expect(result['paint']).to contain_exactly(object_6.stored_pe, object_7.stored_pe)
            end

            it 'returns an empty list of objects for non-existent operations' do
              result = priv_pm.accessible_objects_for_operations(
                user_1,
                [create, 'zagnut'],
                direct_only: true
              )
              # expected:
              # {
              #   'create' => [object_6.stored_pe, object_7.stored_pe],
              #   'zagnut' => [],
              # }
              expect(result.keys).to contain_exactly(create.to_s, 'zagnut')
              expect(result[create.to_s]).to contain_exactly(object_6.stored_pe, object_7.stored_pe)
              expect(result['zagnut']).to eq([])
            end

            context 'filters' do
              let(:filters) { { user_attributes: { color: color_1.color } } }

              it 'they work' do
                result = priv_pm.accessible_objects_for_operations(
                  user_1,
                  [create, paint],
                  filters: filters,
                  direct_only: true
                )
                expect(result).to eq({
                  create.to_s => [object_6.stored_pe],
                  paint.to_s => [object_6.stored_pe],
                })
              end
            end

            context 'prohibitions' do
              let(:cant_create) { priv_pm.create_operation_set('cant_create') }
              let(:filters) { { user_attributes: { color: color_1.color } } }

              before do
                priv_pm.add_assignment(cant_create, create.prohibition)
                priv_pm.add_association(color_2, cant_create, object_6)
              end

              it 'does not return objects with prohibitions' do
                result = priv_pm.accessible_objects_for_operations(
                  user_1,
                  [create, paint],
                  direct_only: true
                )
                # expected:
                # {
                #   create.to_s => [object_7.stored_pe],
                #   paint.to_s => [object_6.stored_pe, object_7.stored_pe],
                # }
                expect(result.keys).to contain_exactly(create.to_s, paint.to_s)
                expect(result[create.to_s]).to contain_exactly(object_7.stored_pe)
                expect(result[paint.to_s]).to contain_exactly(object_6.stored_pe, object_7.stored_pe)
              end

              # prohibition applied via color_2 still blocks create on object_6,
              # even though we are filtering via color_1
              it 'ignores filters for prohibitions' do
                result = priv_pm.accessible_objects_for_operations(
                  user_1,
                  [create, paint],
                  filters: filters,
                  direct_only: true
                )
                expect(result).to eq({
                  create.to_s => [],
                  paint.to_s => [object_6.stored_pe],
                })
              end
            end

            context 'fields' do
              it 'plucks only requested fields' do
                result = priv_pm.accessible_objects_for_operations(
                  user_1,
                  [create, paint],
                  direct_only: true,
                  fields: [:unique_identifier, :id]
                )

                expect(result.keys).to contain_exactly(create.to_s, paint.to_s)
                expect(result[create.to_s]).to contain_exactly(
                  { id: object_6.id, unique_identifier: object_6.unique_identifier },
                  { id: object_7.id, unique_identifier: object_7.unique_identifier }
                )
                expect(result[paint.to_s]).to contain_exactly(
                  { id: object_6.id, unique_identifier: object_6.unique_identifier },
                  { id: object_7.id, unique_identifier: object_7.unique_identifier }
                )
              end

              it 'plucks a single field' do
                result = priv_pm.accessible_objects_for_operations(
                  user_1,
                  [create, paint],
                  direct_only: true,
                  fields: [:unique_identifier]
                )

                expect(result.keys).to contain_exactly(create.to_s, paint.to_s)
                expect(result[create.to_s]).to contain_exactly(
                  { unique_identifier: object_6.unique_identifier },
                  { unique_identifier: object_7.unique_identifier }
                )
                expect(result[paint.to_s]).to contain_exactly(
                  { unique_identifier: object_6.unique_identifier },
                  { unique_identifier: object_7.unique_identifier }
                )
              end

              it 'does not include id implicitly' do
                result = priv_pm.accessible_objects_for_operations(
                  user_1,
                  [create, paint],
                  direct_only: true,
                  fields: [:unique_identifier]
                )

                expect(result.keys).to contain_exactly(create.to_s, paint.to_s)
                expect(result[create.to_s]).to contain_exactly(
                  { unique_identifier: object_6.unique_identifier },
                  { unique_identifier: object_7.unique_identifier }
                )
                expect(result[paint.to_s]).to contain_exactly(
                  { unique_identifier: object_6.unique_identifier },
                  { unique_identifier: object_7.unique_identifier }
                )
              end
            end
          end

          context 'when there are no directly accessible objects' do
            it 'returns empty objects list for each operation' do
              result = priv_pm.accessible_objects_for_operations(
                user_1,
                [create, paint],
                direct_only: true
              )
              expect(result).to eq({
                create.to_s => [],
                paint.to_s => [],
              })
            end
          end
        end

        context 'not direct only' do
          it 'raises ArgumentError' do
            expect { priv_pm.accessible_objects_for_operations(user_1, [create, paint]) }
              .to raise_error(ArgumentError)
          end
        end
      end

      shared_examples 'a single query for accessible objects' do
        before do
          priv_pm.add_association(color_1, creator, object_6)
          priv_pm.add_association(color_2, creator, object_7)
        end

        it 'returns objects accessible via each of multiple given operations' do
          result = priv_pm.accessible_objects_for_operations(
            user_1,
            [create, paint],
            direct_only: true,
            ignore_prohibitions: true,
            fields: [:unique_identifier]
          )

          expect(result.keys).to contain_exactly(create.to_s, paint.to_s)
          expect(result[create.to_s]).to contain_exactly('object_7', 'object_6')
          expect(result[paint.to_s]).to contain_exactly('object_7', 'object_6')
        end

        it 'can handle string operations' do
          result = priv_pm.accessible_objects_for_operations(
            user_1,
            ['create', 'paint'],
            direct_only: true,
            ignore_prohibitions: true,
            fields: [:unique_identifier]
          )

          expect(result.keys).to contain_exactly('create', 'paint')
          expect(result[create.to_s]).to contain_exactly('object_7', 'object_6')
          expect(result[paint.to_s]).to contain_exactly('object_7', 'object_6')
        end

        it 'returns an empty list of objects for non-existent operations' do
          result = priv_pm.accessible_objects_for_operations(
            user_1,
            [create, 'zagnut'],
            direct_only: true,
            ignore_prohibitions: true,
            fields: [:unique_identifier]
          )

          expect(result.keys).to contain_exactly(create.to_s, 'zagnut')
          expect(result[create.to_s]).to contain_exactly('object_7', 'object_6')
          expect(result['zagnut']).to eq([])
        end

        it 'returns a unique list of objects for each operation' do
          result = priv_pm.accessible_objects_for_operations(
            user_1,
            [create, paint],
            direct_only: true,
            ignore_prohibitions: true,
            fields: [:type]
          )

          expect(result.keys).to contain_exactly('create', 'paint')
          expect(result[create.to_s]).to contain_exactly('PolicyMachineStorageAdapter::ActiveRecord::Object')
          expect(result[paint.to_s]).to contain_exactly('PolicyMachineStorageAdapter::ActiveRecord::Object')
        end

        context 'filters' do
          it 'works for a single filter' do
            result = priv_pm.accessible_objects_for_operations(
              user_1,
              [create, paint],
              filters: {
                user_attributes: { color: color_1.color }
              },
              direct_only: true,
              ignore_prohibitions: true,
              fields: [:unique_identifier]
            )

            expect(result).to eq({
              create.to_s => ['object_6'],
              paint.to_s => ['object_6'],
            })
          end

          it 'works for multiple filters' do
            result = priv_pm.accessible_objects_for_operations(
              user_1,
              [create, paint],
              filters: {
                user_attributes: {
                  color: color_1.color,
                  unique_identifier: color_1.unique_identifier,
                  id: color_1.id
                }
              },
              direct_only: true,
              ignore_prohibitions: true,
              fields: [:unique_identifier]
            )

            expect(result).to eq({
              create.to_s => ['object_6'],
              paint.to_s => ['object_6'],
            })
          end
        end
      end

      describe 'accessible_objects_for_operations_function' do
        it_behaves_like 'a single query for accessible objects'

        it 'uses a PostgreSQL function' do
          expect_any_instance_of(PolicyMachineStorageAdapter::ActiveRecord)
            .to receive(:accessible_objects_for_operations_function)

          priv_pm.accessible_objects_for_operations(
            user_1,
            [create, paint],
            direct_only: true,
            ignore_prohibitions: true,
            fields: [:unique_identifier]
          )
        end
      end

      describe 'accessible_objects_for_operations_cte' do
        before do
          allow(PolicyMachineStorageAdapter::ActiveRecord::PolicyElement)
            .to receive(:replica?).and_return(true)
        end

        it_behaves_like 'a single query for accessible objects'

        it 'uses a single CTE' do
          expect(PolicyMachineStorageAdapter::ActiveRecord::PolicyElement)
            .to receive(:accessible_objects_for_operations_cte)
            .and_call_original

          priv_pm.accessible_objects_for_operations(
            user_1,
            [create, paint],
            direct_only: true,
            ignore_prohibitions: true,
            fields: [:unique_identifier]
          )
        end
      end

      describe 'accessible_ancestor_objects' do
        context 'when policy element associations are not provided as an argument' do
          it 'returns objects accessible via the filtered attribute on an object scope' do
            options = {
              filters: { user_attributes: { color: 'green' } },
              key: :unique_identifier
            }

            expect(
              priv_pm.accessible_ancestor_objects(
                user_1,
                create,
                object_2,
                options
              ).map(&:unique_identifier)
            ).to match_array(['object_2', 'object_3', 'object_4'])
          end

          it 'does not return objects that are not accessible via the filtered attribute on an object scope' do
            options = {
              filters: { user_attributes: { color: 'pink' } }
            }

            expect(
              priv_pm.accessible_ancestor_objects(user_1, create, object_2, options)
            ).to be_empty
          end

          context 'prohibitions' do
            let(:cant_create) { priv_pm.create_operation_set('cant_create') }

            before do
              priv_pm.add_assignment(cant_create, create.prohibition)
              priv_pm.add_association(color_3, cant_create, object_3)
            end

            it 'does not return objects with prohibitions' do
              options = {
                filters: { user_attributes: { color: 'green' } },
                key: :unique_identifier
              }

              expect(
                priv_pm.accessible_ancestor_objects(
                  user_1,
                  create,
                  object_2,
                  options
                ).map(&:unique_identifier)
              ).to_not include('object_3')
            end
          end
        end

        context 'when policy element associations are provided as an argument' do
          let(:user_and_descendant_ids) { user_1.descendants.pluck(:id) | [user_1.id] }
          let(:all_peas) do
            PolicyMachineStorageAdapter::ActiveRecord::PolicyElementAssociation.where(user_attribute_id: user_and_descendant_ids)
          end

          it 'only returns objects accessible via the provided policy element associations' do
            expect(
              priv_pm.accessible_ancestor_objects(
                user_1,
                create,
                object_2,
                { associations_with_operation: all_peas }
              ).map(&:unique_identifier)
            ).to match_array(['object_2', 'object_3', 'object_4'])
          end

          context 'prohibitions' do
            before do
              cant_create = priv_pm.create_operation_set('cant_create')
              priv_pm.add_assignment(cant_create, create.prohibition)
              priv_pm.add_association(color_3, cant_create, object_3)
            end

            context 'when the prohibition is in the provided policy element associations' do
              it 'does not return objects with prohibitions' do
                expect(
                  priv_pm.accessible_ancestor_objects(
                    user_1,
                    create,
                    object_2,
                    { associations_with_operation: all_peas }
                  ).map(&:unique_identifier)
                ).to_not include('object_3')
              end
            end

            context 'when the prohibition is not in the provided policy element associations' do
              let(:create_peas) { all_peas.where(operation_set_id: [creator.id]) }

              it 'does not return objects with prohibitions' do
                expect(
                  priv_pm.accessible_ancestor_objects(
                    user_1,
                    create,
                    object_2,
                    { associations_with_operation: create_peas }
                  ).map(&:unique_identifier)
                ).to_not include('object_3')
              end
            end
          end
        end
      end
    end

    describe 'find_all_of_type' do
      let(:pm_uuid) { SecureRandom.uuid }

      it 'accepts an array parameter on a column attribute' do
        search_uuids = [SecureRandom.uuid, SecureRandom.uuid]
        policy_machine_storage_adapter.add_object(search_uuids[0], pm_uuid)
        policy_machine_storage_adapter.add_object(search_uuids[1], pm_uuid)
        policy_machine_storage_adapter.add_object(SecureRandom.uuid, pm_uuid)

        expect(
          policy_machine_storage_adapter.find_all_of_type_object(
            unique_identifier: search_uuids
          ).count
        ).to eq(2)
      end

      context 'when case insensitive' do
        it 'accepts an array parameter on a column attribute' do
          colors = ['burnt_umber', 'mauve']
          policy_machine_storage_adapter.add_object(SecureRandom.uuid, pm_uuid, color: colors[0])
          policy_machine_storage_adapter.add_object(SecureRandom.uuid, pm_uuid, color: colors[1])
          policy_machine_storage_adapter.add_object(SecureRandom.uuid, pm_uuid, color: nil)

          expect(
            policy_machine_storage_adapter.find_all_of_type_object(
              color: colors,
              ignore_case: true
            ).count
          ).to eq(2)
        end
      end

      it 'allows uuid as a parameter' do
        uuid = SecureRandom.uuid
        policy_machine_storage_adapter.add_object(uuid, pm_uuid)

        expect(
          policy_machine_storage_adapter.find_all_of_type_object(uuid: uuid).count
        ).to eq(1)
      end

      context 'when an extra attribute is used' do
        it 'does not warn' do
          expect(Warn).to_not receive(:warn)
          expect(policy_machine_storage_adapter.find_all_of_type_user(color: 'red')).to be_empty
        end

        it 'accepts an array parameter' do
          foos = ['bar', 'baz']
          foos.each do |foo|
            policy_machine_storage_adapter.add_object(SecureRandom.uuid, pm_uuid, foo: foo)
          end
          policy_machine_storage_adapter.add_object(SecureRandom.uuid, pm_uuid, foo: nil)

          result = policy_machine_storage_adapter.find_all_of_type_object(foo: foos)

          expect(result.count).to eq(2)
          foos.each do |foo|
            expect(result.map(&:foo)).to include(foo)
          end
        end

        it 'only returns elements that match the hash' do
          policy_machine_storage_adapter.add_object(SecureRandom.uuid, pm_uuid)
          policy_machine_storage_adapter.add_object(SecureRandom.uuid, pm_uuid, color: 'red')
          policy_machine_storage_adapter.add_object(SecureRandom.uuid, pm_uuid, color: 'blue')
          expect(policy_machine_storage_adapter.find_all_of_type_object(color: 'red')).to be_one
          expect(policy_machine_storage_adapter.find_all_of_type_object(color: nil)).to be_one
          expect(policy_machine_storage_adapter.find_all_of_type_object(color: 'green')).to be_none
          expect(policy_machine_storage_adapter.find_all_of_type_object(color: 'blue').map(&:color)).to eq(['blue'])
        end

        context 'pagination' do
          before do
            10.times {|i| policy_machine_storage_adapter.add_object("uuid_#{i}", pm_uuid, color: 'red') }
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

  describe '#accessible_ancestor_objects' do
    let(:ado_pm) { PolicyMachine.new(name: 'ADO ActiveRecord PM', storage_adapter: PolicyMachineStorageAdapter::ActiveRecord) }

    let!(:grandparent_fish) { ado_pm.create_object('grandparent_fish') }
    let!(:parent_fish) { ado_pm.create_object('parent_fish') }
    let!(:uncle_fish) { ado_pm.create_object('uncle_fish') }
    let!(:cousin_fish) { ado_pm.create_object('cousin_fish') }
    let!(:child_fish_1) { ado_pm.create_object('child_fish_1') }
    let!(:child_fish_2) { ado_pm.create_object('child_fish_2') }

    let!(:read) { ado_pm.create_operation('read') }
    let!(:write) { ado_pm.create_operation('write') }
    let!(:reader) { ado_pm.create_operation_set('reader') }
    let!(:writer) { ado_pm.create_operation_set('writer') }

    let!(:u1) { ado_pm.create_user('u1') }
    let!(:ua) { ado_pm.create_user_attribute('ua') }
    let!(:oa) { ado_pm.create_object_attribute('oa') }

    let(:options) { { key: :unique_identifier } }

    before do
      [grandparent_fish, parent_fish, child_fish_1, cousin_fish].each do |object|
        ado_pm.add_association(ua, reader, object)
      end
      ado_pm.add_association(ua, writer, oa)

      ado_pm.add_assignment(reader, read)
      ado_pm.add_assignment(writer, write)
      ado_pm.add_assignment(u1, ua)

      # Ancestors are accessible from descendants
      ado_pm.add_assignment(parent_fish, grandparent_fish)
      ado_pm.add_assignment(uncle_fish, grandparent_fish)
      ado_pm.add_assignment(cousin_fish, uncle_fish)
      ado_pm.add_assignment(child_fish_1, parent_fish)
      ado_pm.add_assignment(child_fish_2, parent_fish)
      ado_pm.add_assignment(child_fish_1, oa)
    end

    it 'lists all objects with the given privilege for the given user that are ancestors of a specified object' do
      all_accessible_from_grandparent = %w(grandparent_fish parent_fish uncle_fish cousin_fish child_fish_1 child_fish_2)

      expect(ado_pm.accessible_ancestor_objects(u1, read, grandparent_fish, options).map(&:unique_identifier))
        .to match_array(all_accessible_from_grandparent)
      expect(ado_pm.accessible_ancestor_objects(u1, write, parent_fish, options).map(&:unique_identifier))
        .to contain_exactly('child_fish_1')
    end

    it 'lists all objects with the given privilege provided by an out-of-scope descendant' do
      wrestle = ado_pm.create_operation('wrestle')
      wrestler = ado_pm.create_operation_set('wrestler')
      ado_pm.add_assignment(wrestler, wrestle)

      # Give the user 'wrestle' on the highest, out-of-scope node
      ado_pm.add_association(ua, wrestler, grandparent_fish)

      all_accessible_from_parent = %w(parent_fish child_fish_1 child_fish_2)

      expect(ado_pm.accessible_ancestor_objects(u1, wrestle, parent_fish, options).map(&:unique_identifier))
        .to match_array(all_accessible_from_parent)
    end

    it 'does not return objects which are not ancestors of the specified object' do
      all_accessible_from_uncle = ado_pm.accessible_ancestor_objects(u1, read, uncle_fish, options)

      expect(all_accessible_from_uncle.map(&:unique_identifier)).to contain_exactly('uncle_fish', 'cousin_fish')
    end

    it 'lists objects with the given privilege even if the privilege is not present on an intermediate object' do
      bluff = ado_pm.create_operation('blathe')
      bluffer = ado_pm.create_operation_set('blather')
      ado_pm.add_assignment(bluffer, bluff)

      # Give the user 'bluff' on two of the lowest nodes
      ado_pm.add_association(ua, bluffer, cousin_fish)
      ado_pm.add_association(ua, bluffer, child_fish_1)

      all_accessible_from_grandparent = ado_pm.accessible_ancestor_objects(u1, bluff, grandparent_fish, options)
      all_accessible_from_parent = ado_pm.accessible_ancestor_objects(u1, bluff, parent_fish, options)

      # Verify 'bluff' is still visible when not present on intermediate nodes, namely 'uncle' and 'parent'
      expect(all_accessible_from_grandparent.map(&:unique_identifier)).to contain_exactly('child_fish_1', 'cousin_fish')
      expect(all_accessible_from_parent.map(&:unique_identifier)).to contain_exactly('child_fish_1')
    end

    it 'filters objects via substring matching' do
      expect(
        ado_pm.accessible_ancestor_objects(u1,
          read,
          grandparent_fish,
          options.merge(includes: 'parent')
        ).map(&:unique_identifier)
      ).to contain_exactly('grandparent_fish', 'parent_fish')

      expect(
        ado_pm.accessible_ancestor_objects(u1,
          read,
          grandparent_fish,
          options.merge(includes: 'messedupstring')
        ).map(&:unique_identifier)
      ).to be_empty
    end

    context 'cascading operation sets' do
      let!(:speed_write) { ado_pm.create_operation('speed_write') }
      let!(:speed_writer) { ado_pm.create_operation_set('speed_writer') }
      let!(:speediest_write) { ado_pm.create_operation('speediest_write') }
      let!(:speediest_writer) { ado_pm.create_operation_set('speediest_writer') }

      before do
        ado_pm.add_assignment(speed_writer, speed_write)
        ado_pm.add_assignment(writer, speed_writer)
        ado_pm.add_assignment(speediest_writer, speediest_write)
        ado_pm.add_assignment(speed_writer, speediest_writer)
      end

      it 'lists all objects with the given privilege for the given user 1 operation set deep' do
        expect(ado_pm.accessible_ancestor_objects(u1, speed_write, parent_fish, options).map(&:unique_identifier))
          .to contain_exactly('child_fish_1')
      end

      it 'lists all objects with the given privilege for the given user 2 operation sets deep' do
        expect(ado_pm.accessible_ancestor_objects(u1, speediest_write, grandparent_fish, options).map(&:unique_identifier))
          .to contain_exactly('child_fish_1')
      end
    end

    context 'prohibitions' do
      let!(:not_reader) { ado_pm.create_operation_set('not_reader') }

      before do
        ado_pm.add_assignment(not_reader, read.prohibition)
      end

      it 'does not return objects which are ancestors of a prohibited object' do
        ado_pm.add_association(ua, not_reader, parent_fish)
        all_accessible_from_grandparent = %w(grandparent_fish uncle_fish cousin_fish)

        expect(ado_pm.accessible_ancestor_objects(u1, read, grandparent_fish, options).map(&:unique_identifier))
          .to match_array(all_accessible_from_grandparent)
        expect(ado_pm.accessible_ancestor_objects(u1, write, parent_fish, options).map(&:unique_identifier))
          .to contain_exactly('child_fish_1')
      end

      it 'does not return objects which are prohibited by an out-of-scope descendant' do
        ado_pm.add_association(ua, not_reader, grandparent_fish)

        expect(ado_pm.accessible_ancestor_objects(u1, read, parent_fish, options).map(&:unique_identifier))
          .to be_empty
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
    let(:object_attributes) { [object_attr_1, object_attr_2, object_attr_3] }

    let(:object_1) { pm1.create_object('object_1') }
    let(:object_2) { pm1.create_object('object_2') }
    let(:object_3) { pm1.create_object('object_3') }
    let(:objects) { [object_1, object_2, object_3] }

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
          expect(user_1.pluck_from_descendants(**args)).to contain_exactly({ unique_identifier: 'user_attr_1' })
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
          expect(user_attr_1.pluck_from_ancestors(**args)).to contain_exactly(unique_identifier: 'user_1')
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
          expect(user_attr_1.pluck_ancestor_tree(**params)).to eq(plucked_results)
        end

        it 'applies multiple filters if they are supplied' do
          plucked_results = HashWithIndifferentAccess.new('user_attr_9': [])
          params = { fields: [:unique_identifier], filters: { color: 'silver', unique_identifier: 'user_attr_9' } }
          expect(user_attr_1.pluck_ancestor_tree(**params)).to eq(plucked_results)
        end

        it 'returns appropriate results when filters apply to ancestors that have no ancestors themselves' do
          user_attr_10.update(color: 'indigo')
          pm1.add_assignment(user_attr_10, user_attr_1)

          plucked_results = HashWithIndifferentAccess.new(user_attr_10: [])
          params = { fields: [:unique_identifier], filters: { color: 'indigo'} }
          expect(user_attr_1.pluck_ancestor_tree(**params)).to eq(plucked_results)
        end

        it 'returns appropriate results when filters apply to ancestors but not their ancestors' do
          plucked_results = HashWithIndifferentAccess.new(user_attr_4: [], user_attr_5: [], user_attr_6: [])
          params = { fields: [:unique_identifier], filters: { color: 'gold'} }
          expect(user_attr_1.pluck_ancestor_tree(**params)).to eq(plucked_results)
        end

        it 'returns appropriate results when filters apply to no ancestors' do
          params = { fields: [:unique_identifier], filters: { color: 'obsidian'} }
          expect(user_attr_1.pluck_ancestor_tree(**params)).to match_array({})
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
          expect(user_attr_1.pluck_from_parents(**args)).to contain_exactly({ unique_identifier: 'user_1' })
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
          expect(user_1.pluck_from_children(**args)).to contain_exactly({ unique_identifier: 'user_attr_1' })
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
          expect(pm3_user_attr.pluck_from_link_parents(**args)).to contain_exactly({ unique_identifier: 'pm2_operation_1' })
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
          expect(user_1.pluck_from_link_children(**args)).to contain_exactly({ unique_identifier: 'pm2_user' })
        end

        it 'returns appropriate results when filters apply to no link_children' do
          expect(user_1.pluck_from_link_children(fields: [:unique_identifier], filters: { color: 'chartreuse' })).to be_empty
        end
      end
    end
  end

  describe '#associations_filtered_by_operation' do
    let!(:new_pm) { PolicyMachine.new(name: 'AR PM', storage_adapter: PolicyMachineStorageAdapter::ActiveRecord) }

    let(:operation_1) { new_pm.create_operation('operation_1') }
    let(:operation_2) { new_pm.create_operation('operation_2') }
    let(:operation_3) { new_pm.create_operation('operation_3') }
    let(:opset_1) { new_pm.create_operation_set('operation_set_1') }
    let(:opset_2) { new_pm.create_operation_set('operation_set_2') }
    let(:opset_3) { new_pm.create_operation_set('operation_set_3') }

    let(:user_attr) { new_pm.create_user_attribute('user_attr') }

    let(:object_attr_1) { new_pm.create_object_attribute('object_attr_1') }
    let(:object_attr_2) { new_pm.create_object_attribute('object_attr_2') }
    let(:object_attr_3) { new_pm.create_object_attribute('object_attr_3') }

    before do
      new_pm.add_assignment(opset_1, operation_1)
      new_pm.add_assignment(opset_2, operation_2)
      new_pm.add_assignment(opset_3, operation_3)

      new_pm.add_association(user_attr, opset_1, object_attr_1)
      new_pm.add_association(user_attr, opset_2, object_attr_2)
      new_pm.add_association(user_attr, opset_3, object_attr_3)

      new_pm.add_assignment(opset_1, opset_2)
    end

    let(:peas) { PolicyMachineStorageAdapter::ActiveRecord::PolicyElementAssociation.all }
    let(:pea_1) { peas.find_by(operation_set_id: opset_1.id) }
    let(:pea_2) { peas.find_by(operation_set_id: opset_2.id) }
    let(:pea_3) { peas.find_by(operation_set_id: opset_3.id) }

    context 'when provided no policy element associations' do
      it 'does not error' do
        expect { new_pm.associations_filtered_by_operation([], operation_1) }.not_to raise_error
      end

      it 'returns an empty array' do
        expect(new_pm.associations_filtered_by_operation([], operation_1)).to be_empty
      end
    end

    context 'when none of the policy element associations contain the operation' do
      it 'returns an empty array' do
        expect(new_pm.associations_filtered_by_operation(peas, 'fake_operation')).to be_empty
      end
    end

    context 'when at least one of the policy element associations contains the operation' do
      context 'when the operation is in a directly associated operation set' do
        it 'returns only the associations which contain the operation' do
          expect(new_pm.associations_filtered_by_operation(peas, operation_1)).to contain_exactly(pea_1)
        end
      end

      context 'when the operation is in an operation set descendant' do
        it 'returns only the associations which contain the operation' do
          expect(new_pm.associations_filtered_by_operation(peas, operation_2)).to contain_exactly(pea_1, pea_2)
        end
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
          klass.serialize(store: :document, name: :is_arbitrary)
        end

        PolicyMachine::POLICY_ELEMENT_TYPES.each do |type|
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

            it 'stores a JSON representation of an empty hash by default' do
              obj = policy_machine.send("create_#{type}", SecureRandom.uuid)

              sql = "SELECT extra_attributes FROM policy_elements WHERE id = #{obj.id}"
              result = ActiveRecord::Base.connection.execute(sql)
              database_entry = result[0]["extra_attributes"]

              expect(database_entry).to eq('{}')
            end
          end
        end
      end

      describe 'pluck' do
        PolicyMachine::POLICY_ELEMENT_TYPES.each do |type|
          it "plucks the correct data for #{type}" do
            id = "#{type}-pluck-test"
            policy_machine.send("create_#{type}", id)
            data = policy_machine.send(:pluck, type: type, fields: [:unique_identifier], options: { unique_identifier: id })
            expect(data).to eq([id])
          end
        end
      end
    end
  end
end
