require 'policy_machine'
require 'set'
require 'policy_machine/warn_once'

# This class stores policy elements in a SQL database using whatever
# database configuration and adapters are provided by active_record.
# Currently only MySQL and Postgres are supported via this adapter.

begin
  require 'active_record'
rescue LoadError
  active_record_unavailable = true
end

module PolicyMachineStorageAdapter

  class ActiveRecord

    require 'activerecord-import' # Gem for bulk inserts

    # Load the LogicalLink, Assignment, and Adapter classes at runtime because they're
    # implemented differently by different adapters, and which database adapter is active is
    # not always determinable at class definition time. Assignment and LogicalLink must
    # inherit from ActiveRecord::Base and have class methods ancestors_of, descendants_of,
    # and transitive_closure?. Adapter must implement apply_include_condition.
    def self.const_missing(name)
      if %w[Assignment LogicalLink Adapter].include?(name.to_s)
        load_db_adapter!
        const_get(name)
      else
        super
      end
    end

    def self.load_db_adapter!
      require_relative("active_record/#{PolicyElement.configurations[Rails.env]['adapter']}")
    end

    def self.buffering?
      @buffering
    end

    def buffering?
      self.class.buffering?
    end

    def self.start_buffering!
      @buffering = true
    end

    def self.stop_buffering!
      @buffering = false
    end

    def self.buffers
      @buffers ||= {
                     upsert: {},
                     delete: {},
                     assignments: {},
                     assignments_to_remove: {},
                     links: {},
                     links_to_remove: {},
                     associations: []
                   }
    end

    def self.clear_buffers!
      @buffers = nil
    end

    def buffers
      self.class.buffers
    end

    # NB https://github.com/zdennis/activerecord-import/wiki/On-Duplicate-Key-Update
    def self.persist_buffers!
      column_keys = PolicyElement.column_names

      # Because activerecord-import cannot yet handle arbitrary serialized values
      # during import, we set all attributes again in bulk here.  It is important
      # that these changes are mutative, since the default ActiveRecord magic
      # being relied on for assignments and associations will break, otherwise
      buffers[:upsert].values.each { |el| el.attributes = el.attributes.slice(*column_keys) }

      PolicyElement.bulk_destroy(buffers[:delete]) if buffers[:delete].present?
      PolicyElement.bulk_unassign(buffers[:assignments_to_remove]) if buffers[:assignments_to_remove].present?
      PolicyElement.bulk_unlink(buffers[:links_to_remove]) if buffers[:links_to_remove].present?
      if buffers[:upsert].present?
        PolicyElement.import(buffers[:upsert].values, on_duplicate_key_update: column_keys.map(&:to_sym) - [:id])
      end
      PolicyElement.bulk_assign(buffers[:assignments]) if buffers[:assignments].present?
      PolicyElement.bulk_link(buffers[:links]) if buffers[:links].present?
      PolicyElement.bulk_associate(buffers[:associations], buffers[:upsert]) if buffers[:associations].present?

      true #TODO: More useful return value?
    end

    class PolicyElement < ::ActiveRecord::Base
      alias_method :persisted, :persisted?
      singleton_class.send(:alias_method, :active_record_serialize, :serialize)

      # needs unique_identifier, policy_machine_uuid, type, extra_attributes columns
      has_many :assignments, foreign_key: :parent_id, dependent: :destroy
      has_many :logical_links, foreign_key: :link_parent_id, dependent: :destroy
      has_many :filial_ties, class_name: 'Assignment', foreign_key: :child_id
      has_many :link_filial_ties, class_name: 'LogicalLink', foreign_key: :link_child_id
      # these don't actually destroy the relations, just the assignments
      has_many :unfiltered_children, through: :assignments, source: :child, dependent: :destroy
      has_many :unfiltered_parents, through: :filial_ties, source: :parent, dependent: :destroy
      has_many :unfiltered_link_children, through: :logical_links, source: :link_child, dependent: :destroy
      has_many :unfiltered_link_parents, through: :link_filial_ties, source: :link_parent, dependent: :destroy

      attr_accessor :extra_attributes_hash

      active_record_serialize :extra_attributes, JSON

      def method_missing(meth, *args, &block)
        store_attributes
        if respond_to?(meth)
          send(meth, *args)
        elsif meth.to_s[-1] == '='
          @extra_attributes_hash[meth.to_s.chop] = args.first
        else
          super
        end
      end

      def respond_to_missing?(meth, *args)
        store_attributes unless @extra_attributes_hash
        @extra_attributes_hash[meth.to_s] || super
      end

      # Uses ActiveRecord's store method to methodize new attribute keys in extra_attributes
      def store_attributes
        # Do not overwrite accessors for existing columns
        @extra_attributes_hash = extra_attributes
        column_attributes = PolicyElement.column_names.map(&:to_sym)
        self.class.store_accessor(:extra_attributes, @extra_attributes_hash.except(column_attributes).keys)
      end

      def descendants(filters = {})
        assert_valid_filters!(filters)
        Assignment.descendants_of(self).where(filters)
      end

      def ancestors(filters = {})
        assert_valid_filters!(filters)
        Assignment.ancestors_of(self).where(filters)
      end

      def parents(filters = {})
        assert_valid_filters!(filters)
        unfiltered_parents.where(filters)
      end

      def children(filters = {})
        assert_valid_filters!(filters)
        unfiltered_children.where(filters)
      end

      def link_descendants(filters = {})
        assert_valid_filters!(filters)
        LogicalLink.descendants_of(self).where(filters)
      end

      def link_ancestors(filters = {})
        assert_valid_filters!(filters)
        LogicalLink.ancestors_of(self).where(filters)
      end

      def link_parents(filters = {})
        assert_valid_filters!(filters)
        unfiltered_link_parents.where(filters)
      end

      def link_children(filters = {})
        assert_valid_filters!(filters)
        unfiltered_link_children.where(filters)
      end

      def self.serialize(store:, name:, serializer: nil)
        active_record_serialize store, serializer

        store_accessor store, name
      end

      def buffers
        pm_storage_adapter.buffers
      end

      # TODO: support databases that dont support upserts(pg 9.4, etc)
      def self.create_later(attrs, storage_adapter)
        element = new(attrs)

        storage_adapter.buffers[:upsert][element.unique_identifier] = element
      end

      # NB: delete_all in AR bypasses relation logic, which shouldn't matter here.
      def self.bulk_destroy(elements)
        id_groups = elements.reduce(Hash.new { |h,k| h[k] = [] }) do |memo,(_,el)|
          if el.is_a?(UserAttribute) || el.is_a?(ObjectAttribute)
            memo[el.class] << el.id
          end

          memo
        end

        PolicyElement.where(unique_identifier: elements.keys).delete_all

        ids = elements.values.flat_map(&:id)
        Assignment.where(parent_id: ids).delete_all
        Assignment.where(child_id: ids).delete_all

        LogicalLink.where(link_parent_id: ids).delete_all
        LogicalLink.where(link_child_id: ids).delete_all

        PolicyElementAssociation.where(user_attribute_id: id_groups[UserAttribute]).delete_all
        PolicyElementAssociation.where(object_attribute_id: id_groups[ObjectAttribute]).delete_all
      end

      def self.bulk_assign(pairs_hash)
        id_pairs = pairs_hash.values.map { |parent, child| [parent.id, child.id]  }
        Assignment.import([:parent_id, :child_id], id_pairs, on_duplicate_key_ignore: true)
      end

      def self.bulk_unassign(pairs_hash)
        pairs_str = pairs_hash.values.reduce([]) do |memo, (parent, child)|
          parent.persisted? && child.persisted? ? memo + ["(#{parent.id},#{child.id})"] : memo
        end.join(',')
        Assignment.where("(parent_id,child_id) IN (#{pairs_str})").delete_all unless pairs_str.empty?
      end

      def self.bulk_unlink(pairs_hash)
        pairs_str = pairs_hash.values.reduce([]) do |memo, (parent, child)|
          parent.persisted? && child.persisted? ? memo + ["(#{parent.id},#{child.id})"] : memo
        end.join(',')
        LogicalLink.where("(link_parent_id,link_child_id) IN (#{pairs_str})").delete_all unless pairs_str.empty?
      end

      def self.bulk_link(pairs_hash)
        id_pairs = pairs_hash.values.map { |parent, child| [parent.id, child.id, parent.policy_machine_uuid, child.policy_machine_uuid]  }
        import_fields = [:link_parent_id, :link_child_id, :link_parent_policy_machine_uuid, :link_child_policy_machine_uuid]
        LogicalLink.import(import_fields, id_pairs, on_duplicate_key_ignore: true)
      end

      def self.bulk_associate(associations, upsert_buffer)
        associations.map! do |user_attribute, operation_set, object_attribute|
          PolicyElementAssociation.new(
            user_attribute_id: user_attribute.id,
            object_attribute_id: object_attribute.id,
            operation_set_id: operation_set.id)
        end

        PolicyElementAssociation.import(associations, on_duplicate_key_update: PolicyElementAssociation::DUPLICATE_KEY_UPDATE_PARAMS)
      end

      private

      def assert_valid_filters!(filters)
        unless (filters.keys - PolicyElement.column_names.map(&:to_sym)).empty?
          raise ArgumentError, "Provided argument contains invalid keys, valid keys are #{PolicyElement.column_names}"
        end
      end
    end

    class User < PolicyElement
    end

    class UserAttribute < PolicyElement
      has_many :policy_element_associations, dependent: :destroy
    end

    class ObjectAttribute < PolicyElement
      has_many :policy_element_associations, dependent: :destroy
    end

    class Object < ObjectAttribute
    end

    class Operation < PolicyElement
    end

    class OperationSet < PolicyElement
      has_many :policy_element_associations, dependent: :destroy

      def operations
        Assignment.descendants_of(self).where(type: PolicyMachineStorageAdapter::ActiveRecord::Operation.to_s)
      end
    end

    class PolicyClass < PolicyElement
    end

    class PolicyElementAssociation < ::ActiveRecord::Base
      # The index predicate is effectively the 'where' clause of the partial index on policy element associations
      DUPLICATE_KEY_UPDATE_PARAMS = { conflict_target: [:user_attribute_id, :object_attribute_id, :operation_set_id],
                                      index_predicate: 'operation_set_id IS NOT NULL',
                                      columns: [:user_attribute_id, :object_attribute_id, :operation_set_id]
                                    }

      belongs_to :user_attribute
      belongs_to :object_attribute
      belongs_to :operation_set

      def self.add_association(user_attribute, operation_set, object_attribute)
        pea_args = {
          user_attribute_id: user_attribute.id,
          object_attribute_id: object_attribute.id,
          operation_set_id: operation_set.id }
        association = new(pea_args)

        import([association], on_duplicate_key_update: DUPLICATE_KEY_UPDATE_PARAMS)
      end

      def operations
        operation_set.operations
      end
    end

    POLICY_ELEMENT_TYPES = %w(user user_attribute object object_attribute operation operation_set policy_class)

    POLICY_ELEMENT_TYPES.each do |pe_type|
      ##
      # Store a policy element of type pe_type.
      # The unique_identifier identifies the element within the policy machine.
      # The policy_machine_uuid is the uuid of the containing policy machine.
      #

      #TODO: use the new stored attributes approach and a jsonb column for extra_attributes for the postgres adapter
      define_method("add_#{pe_type}") do |unique_identifier, policy_machine_uuid, extra_attributes = {}|
        klass = class_for_type(pe_type)

        stored_attribute_keys = klass.stored_attributes.except(:extra_attributes).values.flatten.map(&:to_s)
        column_keys = klass.attribute_names + stored_attribute_keys

        active_record_attributes = extra_attributes.stringify_keys
        extra_attributes = active_record_attributes.slice!(*column_keys)

        element_attrs = {
          unique_identifier: unique_identifier,
          policy_machine_uuid: policy_machine_uuid,
          extra_attributes: extra_attributes
        }.merge(active_record_attributes)

        self.buffering? ? klass.create_later(element_attrs, self) : klass.create(element_attrs)
      end

      define_method("find_all_of_type_#{pe_type}") do |options = {}|
        conditions = options.slice!(:per_page, :page, :ignore_case).stringify_keys
        extra_attribute_conditions = conditions.slice!(*PolicyElement.column_names)
        include_conditions, conditions = conditions.partition { |k,v| include_condition?(k,v) }
        pe_class = class_for_type(pe_type)

        # Arel matches provides agnostic case insensitive sql for mysql and postgres
        all = if options[:ignore_case]
                conditions.map do |k,v|
                  if ignore_case_applies?(options[:ignore_case], k)
                    pe_class.arel_table[k].matches(v)
                  else
                    pe_class.arel_table[k].eq(v)
                  end
                end.reduce(pe_class.where(nil)) { |rel, e| rel.where(e) }
              else
                pe_class.where(conditions.to_h)
              end

        include_conditions.each do |key, value|
          all = Adapter.apply_include_condition(scope: all, key: key, value: value[:include], klass: class_for_type(pe_type))
        end

        extra_attribute_conditions.each do |key, value|
          Warn.once("WARNING: #{self.class} is filtering #{pe_type} on #{key} in memory, which won't scale well. " \
                    "To move this query to the database, add a '#{key}' column to the policy_elements table " \
                    "and re-save existing records")
          all.to_a.select! { |pe| pe_matches_extra_attributes?(pe, key, value, options[:ignore_case]) }
        end

        # Default to first page if not specified
        if options[:per_page]
          page = options[:page] ? options[:page] : 1
          all = all.order(:id).paginate(page: page, per_page: options[:per_page])
        end

        # TODO: Look into moving this block into previous pagination conditional and test in consuming app
        unless all.respond_to? :total_entries
          all.define_singleton_method(:total_entries) { all.size }
        end

        all
      end

      define_method("pluck_all_of_type_#{pe_type}") do |fields:, options: {}|
        # Fields must include a primary key to avoid ActiveRecord errors
        fields << :id
        method("find_all_of_type_#{pe_type}").call(options).select(*fields)
      end
    end # End of POLICY_ELEMENT_TYPES iteration

    # A value hash where the only key is :include is special.
    # Note: If we start accepting literal hash values this may need to start checking the key's column type
    def include_condition?(key, value)
      value.respond_to?(:keys) && value.keys.map(&:to_sym) == [:include]
    end

    def class_for_type(pe_type)
      @pe_type_class_hash ||= Hash.new { |h,k| h[k] = "PolicyMachineStorageAdapter::ActiveRecord::#{k.camelize}".constantize }
      @pe_type_class_hash[pe_type]
    end

    # Do the pe's stored attributes match the extra_attributes provided in the query
    def pe_matches_extra_attributes?(policy_element, key, value, ignore_case)
      if policy_element.store_attributes
        attr_value = policy_element.extra_attributes_hash[key]

        if ignore_case_applies?(ignore_case, key) && attr_value.is_a?(String) && value.is_a?(String)
          attr_value.downcase == value.downcase
        else
          attr_value == value
        end
      end
    end

    # Allow ignore_case to be a boolean, string, symbol, or array of symbols or strings
    def ignore_case_applies?(ignore_case, key)
      return false if key == 'policy_machine_uuid'
      ignore_case == true || ignore_case.to_s == key || ( ignore_case.respond_to?(:any?) && ignore_case.any? { |k| k.to_s == key } )
    end

    ##
    # Assign src to dst in policy machine.
    # The two policy elements must be persisted policy elements
    #
    def assign(src, dst)
      assert_persisted_policy_element(src, dst)
      if self.buffering?
        assign_later(parent: src, child: dst)
      else
        Assignment.import([:parent_id, :child_id], [[src.id, dst.id]], on_duplicate_key_ignore: true)
      end
    end

    def assign_later(parent:, child:)
      buffers[:assignments].merge!([parent.unique_identifier, child.unique_identifier] => [parent, child])
      :buffered
    end

    ##
    # Assign src to dst. The two policy elements must be persisted policy
    # elements in different policy machines.
    # This is used for logical relationships outside of the policy machine formalism, such as the
    # relationship between a class of operable and a specific instance of it.
    #
    def link(src, dst)
      assert_persisted_policy_element(src, dst)
      if self.buffering?
        link_later(parent: src, child: dst)
      else
        LogicalLink.import(
          [:link_parent_id, :link_child_id, :link_parent_policy_machine_uuid, :link_child_policy_machine_uuid],
          [[src.id, dst.id, src.policy_machine_uuid, dst.policy_machine_uuid]],
          on_duplicate_key_ignore: true
        )
      end
    end

    def link_later(parent:, child:)
      buffers[:links].merge!([parent.unique_identifier, child.unique_identifier] => [parent, child])
      :buffered
    end

    ##
    # Determine if there is a path from src to dst in the policy machine.
    # The two policy elements must be persisted policy elements; otherwise the method should raise
    # an ArgumentError.
    # Returns true if there is a such a path and false otherwise.
    # Should return true if src == dst
    #
    def connected?(src, dst)
      assert_persisted_policy_element(src, dst)
      src == dst || Assignment.transitive_closure?(src, dst)
    end

    ##
    # Determine if there is a path from src to dst in different policy machines.
    # Returns true if there is a such a path and false otherwise.
    # The two policy elements must be persisted policy elements.
    # Should return false if src == dst
    #
    def linked?(src, dst)
      assert_persisted_policy_element(src, dst)

      return false if src == dst

      LogicalLink.transitive_closure?(src, dst)
    end

    ##
    # Disconnect two policy elements in the machine
    # The two policy elements must be persisted policy elements; otherwise the method should raise
    # an ArgumentError.
    # Generally, false will be returned if the assignment didn't exist in the PM in the
    # first place.
    #
    def unassign(src, dst)
      self.buffering? ? unassign_later(src, dst) : unassign_now(src, dst)
    end

    def unassign_now(src, dst)
      assert_persisted_policy_element(src, dst)
      if assignment = src.assignments.where(child_id: dst.id).first
        assignment.destroy
      end
    end

    def unassign_later(src, dst)
      buffers[:assignments].delete([src.unique_identifier, dst.unique_identifier])
      buffers[:assignments_to_remove].merge!([src.unique_identifier, dst.unique_identifier] => [src, dst])
    end


    ##
    # Disconnects two policy elements in different machines.
    #
    def unlink(src, dst)
      self.buffering? ? unlink_later(src, dst) : unlink_now(src, dst)
    end

    def unlink_now(src, dst)
      assert_persisted_policy_element(src, dst)
      if assignment = src.logical_links.where(link_child_id: dst.id).first
        assignment.destroy
      end
    end

    def unlink_later(src, dst)
      buffers[:links].delete([src.unique_identifier, dst.unique_identifier])
      buffers[:links_to_remove].merge!([src.unique_identifier, dst.unique_identifier] => [src, dst])
    end

    ##
    # Remove a persisted policy element. This should remove its assignments and
    # associations but must not cascade to any connected policy elements.
    # Returns true if the delete succeeded.
    #
    def delete(element)
      self.buffering? ? delete_later(element) : element.destroy
    end

    def delete_later(element)
      buffers[:upsert].delete(element.unique_identifier)
      buffers[:delete].merge!(element.unique_identifier => element)
    end

    ##
    # Update the extra_attributes of a persisted policy element.
    # This should only affect attributes corresponding to the keys passed in.
    # Returns true if the update succeeded or was redundant.
    #
    def update(element, changes_hash)
      changes_hash.each { |k,v| element.send("#{k}=",v) }
      self.buffering? ? update_later(element)  : element.save
    end

    def update_later(element)
      buffers[:upsert][element.unique_identifier] = element
    end

    ##
    # Determine if the given node is in the policy machine or not.
    # Returns true or false accordingly.
    # TODO: This seems wrong.
    #
    def element_in_machine?(pe)
      pe.persisted?
    end

    ##
    # Add the given association to the policy map.  If an association between user_attribute
    # and object_attribute already exists, then replace it with that given in the arguments.
    # Returns true if the association was added and false otherwise.
    #
    def add_association(user_attribute, operation_set, object_attribute)
      if self.buffering?
        associate_later(user_attribute, operation_set, object_attribute)
      else
        PolicyElementAssociation.add_association(user_attribute, operation_set, object_attribute)
      end
    end

    #TODO PM uuid potentially useful for future optimization, currently unused
    def associate_later(user_attribute, operation_set, object_attribute)
      buffers[:associations] << [user_attribute, operation_set, object_attribute]
    end

    ##
    # Return an array of all associations in which the given operation is included.
    # Each element of the array should itself be an array in which the first element
    # is the user_attribute member of the association, the second element is a
    # Ruby Set, each element of which is an operation, the third element is the
    # object_attribute member of the association.
    # If no associations are found then the empty array should be returned.
    #
    def associations_with(operation)
      params = { type: PolicyMachineStorageAdapter::ActiveRecord::OperationSet.to_s }
      operation_sets = Assignment.ancestors_of(operation).where(params)
      assocs = PolicyElementAssociation.where(operation_set_id: operation_sets.pluck(:id))

      assocs.map do |assoc|
        assoc.clear_association_cache #TODO Either do this better (touch through HABTM on bulk insert?) or dont do this?
        [assoc.user_attribute, assoc.operation_set, assoc.object_attribute]
      end
    end

    ##
    # Return array of all policy classes which contain the given object_attribute (or object).
    # Return empty array if no such policy classes found.
    def policy_classes_for_object_attribute(object_attribute)
      object_attribute.descendants.merge(PolicyElement.where(type: class_for_type('policy_class')))
    end

    ##
    # Return array of all user attributes which contain the given user.
    # Return empty array if no such user attributes are found.
    def user_attributes_for_user(user)
      user.descendants.merge(PolicyElement.where(type: class_for_type('user_attribute')))
    end

    ##
    # Execute the passed-in block transactionally: any error raised out of the block causes
    # all the block's changes to be rolled back.
    def transaction(&block)
      PolicyElement.transaction(&block)
    end

    ## Optimized version of PolicyMachine#is_privilege?
    # Returns true if the user has the operation on the object
    def is_privilege?(user_or_attribute, operation, object_or_attribute)
      policy_classes_containing_object = policy_classes_for_object_attribute(object_or_attribute)
      operation_id = operation.try(:unique_identifier) || operation.to_s

      if policy_classes_containing_object.size < 2
        !accessible_operations(user_or_attribute, object_or_attribute, operation_id).empty?
      else
        policy_classes_containing_object.all? do |policy_class|
          !accessible_operations(user_or_attribute, object_or_attribute, operation_id).empty?
        end
      end
    end

    ## Optimized version of PolicyMachine#scoped_privileges
    # Returns all operations the user has on the object
    def scoped_privileges(user_or_attribute, object_or_attribute, options = {})
      policy_classes_containing_object = policy_classes_for_object_attribute(object_or_attribute)

      operations =
        if policy_classes_containing_object.size < 2
          accessible_operations(user_or_attribute, object_or_attribute)
        else
          policy_classes_containing_object.flat_map do |policy_class|
            accessible_operations(user_or_attribute, policy_class.ancestors)
          end
        end

      options[:order] ? operations.sort : operations
    end

    def batch_find(policy_object, query = {}, config = {}, &blk)
      method("find_all_of_type_#{policy_object}").call(query).find_in_batches(config, &blk)
    end

    def batch_pluck(policy_object, query: {}, fields:, config: {}, &blk)
      raise(ArgumentError, "must provide fields to pluck") unless fields.present?
      method("pluck_all_of_type_#{policy_object}").call(fields: fields, options: query).find_in_batches(config) do |batch|
        yield batch.map { |elt| elt.attributes.symbolize_keys }
      end
    end

    ## Optimized version of PolicyMachine#accessible_objects
    # Returns all objects the user has the given operation on
    # TODO: Support multiple policy classes here
    def accessible_objects(user_or_attribute, operation, options = {})
      operation = class_for_type('operation').find_by_unique_identifier!(operation.to_s) unless operation.is_a?(class_for_type('operation'))
      permitting_oas = PolicyElement.where(id: operation.policy_element_associations.where(
        user_attribute_id: user_or_attribute.descendants | [user_or_attribute],
      ).select(:object_attribute_id))
      direct_scope = permitting_oas.where(type: class_for_type('object'))
      indirect_scope = Assignment.ancestors_of(permitting_oas).where(type: class_for_type('object'))
      if inclusion = options[:includes]
        direct_scope = Adapter.apply_include_condition(scope: direct_scope, key: options[:key], value: inclusion, klass: class_for_type('object'))
        indirect_scope = Adapter.apply_include_condition(scope: indirect_scope, key: options[:key], value: inclusion, klass: class_for_type('object'))
      end
      candidates = direct_scope | indirect_scope
      if options[:ignore_prohibitions] || !(prohibition = class_for_type('operation').find_by_unique_identifier("~#{operation.unique_identifier}"))
        candidates
      else
        candidates - accessible_objects(user_or_attribute, prohibition, options.merge(ignore_prohibitions: true))
      end
    end

    private

    def prohibition_for(operation)
      operation_id = operation.try(:unique_identifier) || operation.to_s
      PolicyMachineStorageAdapter::ActiveRecord::Operation.find_by_unique_identifier("~#{operation_id}")
    end

    def accessible_operations(user_or_attribute, object_or_attribute, operation_id = nil)
      transaction_without_mergejoin do
        user_attribute_ids = Assignment.descendants_of(user_or_attribute).pluck(:id) | [user_or_attribute.id]
        object_attribute_ids = Assignment.descendants_of(object_or_attribute).pluck(:id) | [object_or_attribute.id]

        associations =
          PolicyElementAssociation.where(
            user_attribute_id: user_attribute_ids,
            object_attribute_id: object_attribute_ids
          )

        prms = { type: PolicyMachineStorageAdapter::ActiveRecord::Operation.to_s }
        prms.merge!(unique_identifier: operation_id) if operation_id

        Assignment.descendants_of(associations.map(&:operation_set)).where(prms)
      end
    end

    def assert_persisted_policy_element(*arguments)
      arguments.each do |argument|
        raise ArgumentError, "expected policy elements, got #{argument}" unless argument.is_a?(PolicyElement)
      end
    end

    def transaction_without_mergejoin(&block)
      if PolicyMachineStorageAdapter::ActiveRecord::Assignment.connection.is_a? ::ActiveRecord::ConnectionAdapters::PostgreSQLAdapter
        PolicyMachineStorageAdapter::ActiveRecord::Assignment.transaction do
          PolicyMachineStorageAdapter::ActiveRecord::Assignment.connection.execute("set local enable_mergejoin = false")
          yield
        end
      else
        yield
      end
    end

  end
end unless active_record_unavailable
