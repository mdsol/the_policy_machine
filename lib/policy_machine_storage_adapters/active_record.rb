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

    class ApplicationRecord < ::ActiveRecord::Base
      require 'will_paginate/active_record'
      self.abstract_class = true
    end

    class PolicyElement < ApplicationRecord
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
        assert_valid_attributes!(filters.keys)
        Assignment.descendants_of(self).where(filters)
      end

      def ancestors(filters = {})
        assert_valid_attributes!(filters.keys)
        Assignment.ancestors_of(self).where(filters)
      end

      def parents(filters = {})
        assert_valid_attributes!(filters.keys)
        unfiltered_parents.where(filters)
      end

      def children(filters = {})
        assert_valid_attributes!(filters.keys)
        unfiltered_children.where(filters)
      end

      def link_descendants(filters = {})
        assert_valid_attributes!(filters.keys)
        LogicalLink.descendants_of(self).where(filters)
      end

      def link_ancestors(filters = {})
        assert_valid_attributes!(filters.keys)
        LogicalLink.ancestors_of(self).where(filters)
      end

      def link_parents(filters = {})
        assert_valid_attributes!(filters.keys)
        unfiltered_link_parents.where(filters)
      end

      def link_children(filters = {})
        assert_valid_attributes!(filters.keys)
        unfiltered_link_children.where(filters)
      end

      # A series of methods of the form "pluck_from_graph_traversal" which pluck the specified
      # fields from an element's relatives; returns an array of { attribute => value } hashes.
      %w(
        descendants
        ancestors
        parents
        children
        link_descendants
        link_ancestors
        link_parents
        link_children
      ).each do |graph_method|
        define_method("pluck_from_#{graph_method}") do |filters: {}, fields:|
          raise(ArgumentError.new("Must provide at least one field to pluck")) unless fields.present?

          assert_valid_attributes!(filters.keys)
          assert_valid_attributes!(fields)

          plucked_values = public_send(graph_method, filters).pluck(*fields)

          if fields.size > 1
            plucked_values.map { |values| HashWithIndifferentAccess[fields.zip(values)] }
          else
            field = fields.first
            plucked_values.map { |value| HashWithIndifferentAccess[field, value] }
          end
        end
      end

      # This method plucks the attributes of your ancestors' ancestors, along with the
      # relationships among those ancestors.
      def pluck_ancestor_tree(filters: {}, fields:)
        raise(ArgumentError.new("Must provide at least one field to pluck")) unless fields.present?

        assert_valid_attributes!(filters.keys)
        assert_valid_attributes!(fields)

        id_tree = get_ancestor_id_tree([id])
        id_tree.delete(id.to_s)

        fields_to_pluck = [:id, :unique_identifier] | fields
        plucked_policy_elements = PolicyElement.where(id: id_tree.keys).where(filters).pluck(*fields_to_pluck)

        # Convert the plucked attribute arrays into attribute hashes and merge them into the id subtree
        id_attribute_tree = zip_attributes_into_id_tree(id_tree, fields_to_pluck - [:id], plucked_policy_elements)

        # For each ancestor hash, convert all instances of 'id' to 'unique_identifier'
        # and replace each relative's id with that relative's attributes
        id_attribute_tree.each_with_object({}) do |(_, policy_element_attrs), memo|
          if policy_element_attrs.present? && policy_element_attrs.is_a?(Hash)
            ancestral_attributes = select_relative_attributes(id_attribute_tree, policy_element_attrs[:relative_ids])
            memo[policy_element_attrs[:unique_identifier]] = ancestral_attributes
          end
        end
      end

      def self.serialize(store:, name:, serializer: nil)
        # Use the passed serializer if present, otherwise use Rails' default serialization
        active_record_serialize store, serializer if serializer

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

      def assert_valid_attributes!(attributes)
        unless (attributes.map(&:to_sym) - PolicyElement.column_names.map(&:to_sym)).empty?
          raise ArgumentError, "Provided argument contains invalid keys, valid keys are #{PolicyElement.column_names}"
        end
      end

      # Returns a hash containing the ancestors of the root nodes, with the interstitial
      # ancestor relationships represented by the key/value pairs.
      def get_ancestor_id_tree(root_nodes)
        Assignment.find_ancestor_ids(root_nodes).each_with_object({}) do |row, ancestor_id_tree|
          id_array = row['ancestor_ids'].tr('{}','').split(',')
          id_array.each { |ancestor_id| ancestor_id_tree[ancestor_id] ||= [] }
          ancestor_id_tree[row['id'].to_s] = id_array
        end
      end

      # Zip an array of attributes into an id tree, with interstitial relationships preserved
      # under the "relative_ids" key
      def zip_attributes_into_id_tree(id_tree, plucked_fields, plucked_attributes)
        plucked_attributes.each_with_object({}) do |policy_element_attrs, id_attribute_tree|
          # Convert [1, "blue", "user_1"] into { color: "blue", uuid: "user_1" }
          policy_element_id = policy_element_attrs[0].to_s
          attribute_hash = HashWithIndifferentAccess[plucked_fields.zip(policy_element_attrs.drop(1))]
          id_attribute_tree[policy_element_id] = attribute_hash.merge(relative_ids: id_tree[policy_element_id])
        end
      end

      def select_relative_attributes(id_attribute_tree, relative_ids)
        relative_ids.each_with_object([]) do |relative_id, attribute_array|
          relative_attributes = id_attribute_tree[relative_id]
          if relative_attributes && relative_attributes.is_a?(Hash)
            attribute_array << relative_attributes.except(:relative_ids)
          end
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

    class PolicyElementAssociation < ApplicationRecord
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
        # Change :uuid key to :unique_identifier (the real column name)
        options[:unique_identifier] = options.delete(:uuid) if options[:uuid]

        # Build the primary hash of find_all conditions
        conditions = options.slice!(:per_page, :page, :ignore_case).stringify_keys

        # Separate conditions on PolicyElement columns from conditions on the extra_attributes column
        extra_attribute_conditions = conditions.slice!(*PolicyElement.column_names)

        # Partition strict conditions and inclusion conditions
        include_conditions, conditions = conditions.partition { |k,v| include_condition?(k,v) }

        # Generated PolicyElement class
        pe_class = class_for_type(pe_type)

        relation = build_active_record_relation(
                    pe_class: pe_class,
                    conditions: conditions,
                    ignore_case: options[:ignore_case]
                  )

        relation = filter_by_include_conditions(
                    scope: relation,
                    include_conditions: include_conditions,
                    klass: class_for_type(pe_type)
                  )

        relation = filter_by_extra_attributes(
                    scope: relation,
                    extra_attribute_conditions: extra_attribute_conditions,
                    pe_class: pe_class,
                    ignore_case: options[:ignore_case]
                  )

        relation = paginate_scope(scope: relation, options: options)

        # TODO: Look into moving this block into previous pagination conditional and test in consuming app
        unless relation.respond_to? :total_entries
          relation.define_singleton_method(:total_entries) { relation.size }
        end

        relation
      end

      define_method("pluck_all_of_type_#{pe_type}") do |fields:, options: {}|
        # Fields must include a primary key to avoid ActiveRecord errors
        fields << :id
        method("find_all_of_type_#{pe_type}").call(options).select(*fields)
      end
    end # End of POLICY_ELEMENT_TYPES iteration

    def class_for_type(pe_type)
      @pe_type_class_hash ||= Hash.new { |h,k| h[k] = "PolicyMachineStorageAdapter::ActiveRecord::#{k.camelize}".constantize }
      @pe_type_class_hash[pe_type]
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
        assoc.send(:clear_association_cache) #TODO Either do this better (touch through HABTM on bulk insert?) or dont do this?
        [assoc.user_attribute, assoc.operation_set, assoc.object_attribute]
      end
    end

    ##
    # Return array of all policy classes which contain the given object_attribute (or object).
    # Return empty array if no such policy classes found.
    def policy_classes_for_object_attribute(object_attribute)
      object_attribute.descendants.merge(PolicyElement.where(type: class_for_type('policy_class').name))
    end

    def policy_classes_for_object_attribute_descendants(object_attribute_descendants)
      object_attribute_descendants.merge(PolicyElement.where(type: class_for_type('policy_class').name))
    end

    ##
    # Return array of all user attributes which contain the given user.
    # Return empty array if no such user attributes are found.
    def user_attributes_for_user(user)
      user.descendants.merge(PolicyElement.where(type: class_for_type('user_attribute').name))
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
      operation_id = operation.try(:unique_identifier) || operation.to_s

      object_attribute_descendants = object_or_attribute.descendants
      policy_classes_containing_object = policy_classes_for_object_attribute_descendants(object_attribute_descendants)
      object_attribute_ids = object_attribute_descendants.pluck(:id) | [object_or_attribute.id]

      if policy_classes_containing_object.size < 2
        !faster_accessible_operations(user_or_attribute, object_attribute_ids, operation_id).empty?
      else
        policy_classes_containing_object.all? do |policy_class|
          !accessible_operations(user_or_attribute, object_or_attribute, operation_id).empty?
        end
      end
    end

    ## Optimized version of PolicyMachine#is_privilege_with_filters?
    # Returns true if the user has the operation on the object, but only if the privilege
    # can be derived via a user attribute that passes the filter
    def is_filtered_privilege?(user_or_attribute, operation, object_or_attribute, filters: {}, options: {})
      policy_classes_containing_object = policy_classes_for_object_attribute(object_or_attribute)
      operation_id = operation.try(:unique_identifier) || operation.to_s

      if policy_classes_containing_object.size < 2
        !accessible_operations(user_or_attribute, object_or_attribute, operation_id, filters: filters).empty?
      else
        raise 'is_filtered_privilege? does not support multiple policy classes!'
      end
    end

    ## Optimized version of PolicyMachine#scope_privileges
    # Returns all operations the user has on the object
    def scoped_privileges(user_or_attribute, object_or_attribute, options = {})
      policy_classes_containing_object = policy_classes_for_object_attribute(object_or_attribute)

      operations =
        if policy_classes_containing_object.size < 2
          accessible_operations(user_or_attribute, object_or_attribute, filters: options[:filters])
        else
          policy_classes_containing_object.flat_map do |policy_class|
            accessible_operations(user_or_attribute, policy_class.ancestors, filters: options[:filters])
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
      candidates = objects_for_user_or_attribute_and_operation(user_or_attribute, operation, options)

      if options[:ignore_prohibitions] || !(prohibition = prohibition_for(operation))
        candidates
      else
        # Do not use the filter when checking prohibitions
        preloaded_options = options.except(:filters).merge(ignore_prohibitions: true)
        candidates - accessible_objects(user_or_attribute, prohibition, preloaded_options)
      end
    end

    # Version of accessible_objects which only returns objects that are
    # ancestors of a specified root object or the object itself
    def accessible_ancestor_objects(user_or_attribute, operation, root_object, options = {})
      # If the root_object is a generic PM::Object, convert it the appropriate storage adapter Object
      root_object = root_object.try(:stored_pe) || root_object

      # The final set of accessible objects must be ancestors of the root_object; avoid
      # duplicate ancestor calls when possible
      ancestor_objects = options[:ancestor_objects]
      ancestor_objects ||= root_object.ancestors(type: class_for_type('object').name) + [root_object]

      # Short-circuit and return all ancestors (minus prohibitions) if the user_or_attribute
      # is authorized on the root node
      if options[:filters].nil? && is_privilege?(user_or_attribute, operation, root_object)
        return all_ancestor_objects(user_or_attribute, operation, root_object, ancestor_objects, options)
      end

      all_accessible_objects = objects_for_user_or_attribute_and_operation(user_or_attribute, operation, options)
      candidates = all_accessible_objects & ancestor_objects

      if options[:ignore_prohibitions] || !(prohibition = prohibition_for(operation))
        candidates
      else
        # Do not use the filter when checking prohibitions
        preloaded_options = options.except(:filters).merge(ignore_prohibitions: true)
        # If ancestor objects are filtered, preloaded ancestor objects cannot be used when checking prohibitions
        preloaded_options.merge!(ancestor_objects: ancestor_objects) unless options[:filters]

        candidates - accessible_ancestor_objects(user_or_attribute, prohibition, root_object, preloaded_options)
      end
    end

    private

    # Returns an array of all the objects accessible for a given user or attribute and operation
    def objects_for_user_or_attribute_and_operation(user_or_attribute, operation, options)
      associations = associations_for_user_or_attribute(user_or_attribute, options)
      filtered_associations = associations_filtered_by_operation(associations, operation)
      build_accessible_object_scope(filtered_associations, options)
    end

    # Gets the associations related to the given user or attribute or its descendants
    def associations_for_user_or_attribute(user_or_attribute, options)
      user_attribute_filter = options[:filters][:user_attributes] if options[:filters] && options[:filters][:user_attributes]

      user_attribute_ids = user_or_attribute.descendants.where(user_attribute_filter).pluck(:id) | [user_or_attribute.id]
      PolicyElementAssociation.where(user_attribute_id: user_attribute_ids)
    end

    # Filters a list of associations to those related to a given operation
    def associations_filtered_by_operation(associations, operation)
      operation_id = operation.try(:unique_identifier) || operation.to_s

      operation_set_ids = associations.pluck(:operation_set_id)

      filtered_operation_set_ids = Assignment.filter_operation_set_list_by_assigned_operation(operation_set_ids, operation_id)

      associations.where(operation_set_id: filtered_operation_set_ids)
    end

    # Builds an array of PolicyElement objects within the scope of a given
    # array of associations
    def build_accessible_object_scope(associations, options = {})
      permitting_oas = PolicyElement.where(id: associations.pluck(:object_attribute_id))

      # Direct scope: the set of objects on which the operator is directly assigned
      direct_scope = permitting_oas.where(type: class_for_type('object').name)
      # Indirect scope: the set of objects which the operator can access via ancestral hierarchy
      indirect_scope = Assignment.ancestors_of(permitting_oas).where(type: class_for_type('object').name)

      if inclusion = options[:includes]
        direct_scope = build_inclusion_scope(direct_scope, options[:key], inclusion)
        indirect_scope = build_inclusion_scope(indirect_scope, options[:key], inclusion)
      end

      direct_scope | indirect_scope
    end

    def build_inclusion_scope(scope, key, value)
      Adapter.apply_include_condition(scope: scope, key: key, value: value, klass: class_for_type('object'))
    end

    # Given a policy element class and a set of conditions, returns an
    # ActiveRecord_Relation with those conditions applied
    def build_active_record_relation(pe_class:, conditions:, ignore_case:)
      if ignore_case
        # If any condition is case-insensitive, the nodes need to be built
        # individually with Arel.
        build_ignore_case_relation(
          pe_class: pe_class,
          conditions: conditions,
          ignore_case: ignore_case
        )
      else
        # If all conditions are case-sensitive, a direct where call can be used.
        pe_class.where(conditions.to_h)
      end
    end

    def build_ignore_case_relation(pe_class:, conditions:, ignore_case:)
      # Conditions hash to array so it can be reduced
      condition_array = conditions.to_a
      # Initialize an "empty" relation
      starting_relation = pe_class.where(nil)

      # Reduce the conditions array to a single relation by building Arel nodes
      condition_array.reduce(starting_relation) do |relation, condition_pair|
        key, value = condition_pair

        arel_node = if ignore_case_applies?(ignore_case, key)
                      build_arel_insensitive(pe_class: pe_class, key: key, value: value)
                    else
                      build_arel_sensitive(pe_class: pe_class, key: key, value: value)
                    end

        relation.where(arel_node)
      end
    end

    # Build Arel nodes using case-insensitive matching
    def build_arel_insensitive(pe_class:, key:, value:)
      if value.is_a?(Array)
        pe_class.arel_table[key].matches_any(value)
      else
        pe_class.arel_table[key].matches(value)
      end
    end

    # Build Arel nodes using case-sensitive equality checking
    def build_arel_sensitive(pe_class:, key:, value:)
      # Arel blows up with empty array passed to eq_any
      # See: https://github.com/rails/arel/issues/368
      if value.is_a?(Array) && value.present?
        pe_class.arel_table[key].eq_any(value)
      elsif value.is_a?(Array) && value.empty?
        ::Arel::Nodes::SqlLiteral.new("(NULL)")
      else
        pe_class.arel_table[key].eq(value)
      end
    end

    # Iterate over the input scope and return elements that match the extra
    # attribute conditions
    def filter_by_extra_attributes(scope:, extra_attribute_conditions:, pe_class:, ignore_case:)
      if extra_attribute_conditions.empty?
        scope
      else
        ids = scope.reduce([]) do |memo, policy_element|
          pe_within_scope = extra_attribute_conditions.all? do |key, value|
            pe_matches_extra_attributes?(policy_element, key, value, ignore_case)
          end

          pe_within_scope ? memo.push(policy_element.id) : memo
        end

        pe_class.where(id: ids)
      end
    end

    # Check inclusion for each include condition using the Adapter
    def filter_by_include_conditions(scope:, include_conditions:, klass:)
      include_conditions.each do |key, value|
        scope = Adapter.apply_include_condition(
          scope: scope,
          key: key,
          value: value[:include],
          klass: klass
        )
      end
      scope
    end

    # Paginate the scope if options hash has pagination information
    def paginate_scope(scope:, options:)
      if options[:per_page]
        page = options[:page] || 1
        scope = scope.order(:id).paginate(page: page, per_page: options[:per_page])
      end
      scope
    end

    # A value hash where the only key is :include is special.
    # Note: If we start accepting literal hash values this may need to start checking the key's column type
    def include_condition?(key, value)
      value.respond_to?(:keys) && value.keys.map(&:to_sym) == [:include]
    end

    # Check if the PolicyElement's extra_attributes column includes the passed
    # key and value
    def pe_matches_extra_attributes?(policy_element, key, value, ignore_case)
      if policy_element.store_attributes
        attr_value = policy_element.extra_attributes_hash[key]

        if value.is_a?(Array)
          value.any? do |v|
            extra_attribute_match(
              ignore_case: ignore_case,
              key: key,
              value_1: attr_value,
              value_2: v
            )
          end
        else
          extra_attribute_match(
            ignore_case: ignore_case,
            key: key,
            value_1: attr_value,
            value_2: value
          )
        end
      end
    end

    def extra_attribute_match(ignore_case:, key:, value_1:, value_2:)
      if ignore_case_applies?(ignore_case, key) && value_1.is_a?(String) && value_2.is_a?(String)
        value_1.downcase == value_2.downcase
      else
        value_1 == value_2
      end
    end

    # Allow ignore_case to be a boolean, string, symbol, or array of symbols or strings
    def ignore_case_applies?(ignore_case, key)
      return false if key == 'policy_machine_uuid'

      return true if ignore_case == true

      # e.g. ignore_case = :name
      return true if ignore_case.to_s == key

      # e.g. ignore_case = [:name, :parent_uri]
      return true if ignore_case.respond_to?(:any?) && ignore_case.any? { |k| k.to_s == key }

      false
    end

    def prohibition_for(operation)
      operation_id = operation.try(:unique_identifier) || operation.to_s
      PolicyMachineStorageAdapter::ActiveRecord::Operation.find_by_unique_identifier("~#{operation_id}")
    end

    def accessible_operations(user_or_attribute, object_or_attribute, operation_id = nil, filters: {})
      transaction_without_mergejoin do
        user_attribute_filter = filters[:user_attributes] if filters

        user_attribute_ids = Assignment.descendants_of(user_or_attribute).where(user_attribute_filter).pluck(:id) | [user_or_attribute.id]
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

    def faster_accessible_operations(user_or_attribute, object_attribute_ids, operation_id = nil, filters: {})
      transaction_without_mergejoin do
        user_attribute_filter = filters[:user_attributes] if filters

        user_attribute_ids = Assignment.descendants_of(user_or_attribute).where(user_attribute_filter).pluck(:id) | [user_or_attribute.id]

        operation_set_ids =
          PolicyElementAssociation.where(
            user_attribute_id: user_attribute_ids,
            object_attribute_id: object_attribute_ids
          ).pluck(:operation_set_id)

        prms = { type: PolicyMachineStorageAdapter::ActiveRecord::Operation.to_s }
        prms.merge!(unique_identifier: operation_id) if operation_id

        Assignment.descendants_of(operation_set_ids).where(prms)
      end
    end

    # Filter all ancestor objects from a common root by the provided include condition
    # and/or pre-existing prohibitions
    def all_ancestor_objects(user_or_attribute, operation, root_object, ancestor_objects, options)
      apply_include_condition!(ancestor_objects, options[:key], options[:includes])

      if !options[:ignore_prohibitions] && prohibition = prohibition_for(operation)
        prohibited_ancestor_objects = accessible_ancestor_objects(
          user_or_attribute,
          prohibition,
          root_object,
          options.merge(ignore_prohibitions: true, ancestor_objects: ancestor_objects)
        )
        ancestor_objects - prohibited_ancestor_objects
      else
        ancestor_objects
      end
    end

    # Reduce a set of objects to those including a specific value for a specified key
    # e.g. includes_key = 'name', includes_value = 'example_name'
    def apply_include_condition!(objects, includes_key, includes_value)
      if includes_key && includes_value
        objects.select! { |obj| obj.send(includes_key.to_sym).include?(includes_value) }
      end
      objects
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
