require 'policy_machine'
require 'set'

# This class stores policy elements in a SQL database using whatever
# database configuration and adapters are provided by active_record.
# Currently only MySQL is supported via this adapter.

begin
  require 'active_record'
rescue LoadError
  active_record_unavailable = true
end

module PolicyMachineStorageAdapter

  class ActiveRecord

    class PolicyElement < ::ActiveRecord::Base
      alias :persisted :persisted?
      # needs unique_identifier, policy_machine_uuid, type, extra_attributes columns
      has_many :assignments, foreign_key: :parent_id, dependent: :destroy
      has_many :children, through: :assignments, dependent: :destroy #this doesn't actually destroy the children, just the assignment
      has_many :transitive_closure, foreign_key: :ancestor_id
      has_many :inverse_transitive_closure, class_name: :"PolicyMachineStorageAdapter::ActiveRecord::TransitiveClosure", foreign_key: :descendant_id
      has_many :descendants, through: :transitive_closure
      has_many :ancestors, through: :inverse_transitive_closure
      attr_accessible :unique_identifier, :policy_machine_uuid, :extra_attributes
      attr_accessor :extra_attributes_hash
      before_save :serialize_extra_attributes_hash

      def method_missing(meth, *args, &block)
        methodize_extra_attributes_hash
        if respond_to?(meth)
          send(meth, *args)
        elsif meth.to_s[-1] == '='
          @extra_attributes_hash[meth.to_s] = args.first
          methodize_extra_attributes_hash
        else
          super
        end
      end

      def respond_to_missing?(meth, *args)
        methodize_extra_attributes_hash unless @extra_attributes_hash
        @extra_attributes_hash[meth.to_s] || super
      end

      def methodize_extra_attributes_hash
        @extra_attributes_hash = JSON.parse(self.extra_attributes, quirks_mode: true) if self.extra_attributes
        @extra_attributes_hash ||= {}
        @extra_attributes_hash.extract!(*self.class.column_names).each do |key, value|
          send("#{key}=", value) unless value.nil?
        end
        @extra_attributes_hash.each do |key, value|
          define_singleton_method key, lambda {@extra_attributes_hash[key.to_s]}
          define_singleton_method "#{key}=", lambda { | value | @extra_attributes_hash[key.to_s] = value }
        end
      end

      def serialize_extra_attributes_hash
        methodize_extra_attributes_hash unless @extra_attributes_hash
        self.extra_attributes = extra_attributes_hash.to_json
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
      has_and_belongs_to_many :policy_element_associations, class_name: :"PolicyMachineStorageAdapter::ActiveRecord::PolicyElementAssociation"
    end

    class PolicyClass < PolicyElement
    end

    class PolicyElementAssociation < ::ActiveRecord::Base
      # requires a join table (should be indexed!)
      has_and_belongs_to_many :operations, class_name: :"PolicyMachineStorageAdapter::ActiveRecord::Operation"
      belongs_to :user_attribute
      belongs_to :object_attribute
    end

    class TransitiveClosure < ::ActiveRecord::Base
      self.table_name = 'transitive_closure'
      # needs ancestor_id, descendant_id columns
      belongs_to :ancestor, class_name: :PolicyElement
      belongs_to :descendant, class_name: :PolicyElement
    end

    class Assignment < ::ActiveRecord::Base
      attr_accessible :child_id
      # needs parent_id, child_id columns
      after_create :add_to_transitive_closure
      after_destroy :remove_from_transitive_closure
      belongs_to :parent, class_name: :PolicyElement
      belongs_to :child, class_name: :PolicyElement

      def self.transitive_closure?(ancestor, descendant)
        TransitiveClosure.exists?(ancestor_id: ancestor.id, descendant_id: descendant.id)
      end

      def add_to_transitive_closure
        connection.execute("Insert ignore into transitive_closure values (#{parent_id}, #{child_id})")
        connection.execute("Insert ignore into transitive_closure
             select parents_ancestors.ancestor_id, childs_descendants.descendant_id from
              transitive_closure parents_ancestors,
              transitive_closure childs_descendants
             where
              (parents_ancestors.descendant_id = #{parent_id} or parents_ancestors.ancestor_id = #{parent_id})
              and (childs_descendants.ancestor_id = #{child_id} or childs_descendants.descendant_id = #{child_id})")
      end

      def remove_from_transitive_closure
        parents_ancestors = connection.execute("Select ancestor_id from transitive_closure where descendant_id=#{parent_id}")
        childs_descendants = connection.execute("Select descendant_id from transitive_closure where ancestor_id=#{child_id}")
        parents_ancestors = parents_ancestors.to_a.<<(parent_id).join(',')
        childs_descendants = childs_descendants.to_a.<<(child_id).join(',')

        connection.execute("Delete from transitive_closure where
          ancestor_id in (#{parents_ancestors}) and
          descendant_id in (#{childs_descendants}) and
          not exists (Select * from assignments where parent_id=ancestor_id and child_id=descendant_id)
        ")

        connection.execute("Insert ignore into transitive_closure
            select ancestors_surviving_relationships.ancestor_id, descendants_surviving_relationships.descendant_id
            from
              transitive_closure ancestors_surviving_relationships,
              transitive_closure descendants_surviving_relationships
            where
              (ancestors_surviving_relationships.ancestor_id in (#{parents_ancestors}))
              and (descendants_surviving_relationships.descendant_id in (#{childs_descendants}))
              and (ancestors_surviving_relationships.descendant_id = descendants_surviving_relationships.ancestor_id)
        ")
      end

    end

    POLICY_ELEMENT_TYPES = %w(user user_attribute object object_attribute operation policy_class)

    POLICY_ELEMENT_TYPES.each do |pe_type|
      ##
      # Store a policy element of type pe_type.
      # The unique_identifier identifies the element within the policy machine.
      # The policy_machine_uuid is the uuid of the containing policy machine.
      #
      define_method("add_#{pe_type}") do |unique_identifier, policy_machine_uuid, extra_attributes = {}|
        active_record_attributes = extra_attributes.stringify_keys
        extra_attributes = active_record_attributes.slice!(*PolicyElement.column_names)
        element_attrs = {
          :unique_identifier => unique_identifier,
          :policy_machine_uuid => policy_machine_uuid,
          :extra_attributes => extra_attributes.to_json
        }.merge(active_record_attributes)
        class_for_type(pe_type).create(element_attrs, without_protection: true)
      end

      define_method("find_all_of_type_#{pe_type}") do |options = {}|
        conditions = options.slice!(:per_page, :page).stringify_keys
        extra_attribute_conditions = conditions.slice!(*PolicyElement.column_names)
        all = class_for_type(pe_type).where(conditions)
        extra_attribute_conditions.each do |key, value|
          warn "WARNING: #{self.class} is filtering #{pe_type} on #{key} in memory, which won't scale well. " <<
            "To move this query to the database, add a '#{key}' column to the policy_elements table " <<
            "and re-save existing records"
          all.select!{ |pe| pe.methodize_extra_attributes_hash and pe.extra_attributes_hash[key] == value }
        end
        # Default to first page if not specified
        if options[:per_page]
          page = options[:page] ? options[:page] : 1
          all = all.order.paginate(page: page, per_page: options[:per_page])
        end
        all
      end
    end

    def class_for_type(pe_type)
      @pe_type_class_hash ||= Hash.new { |h,k| h[k] = "PolicyMachineStorageAdapter::ActiveRecord::#{k.camelize}".constantize }
      @pe_type_class_hash[pe_type]
    end

    ##
    # Assign src to dst in policy machine.
    # The two policy elements must be persisted policy elements
    # Returns true if the assignment occurred, false otherwise.
    #
    def assign(src, dst)
      assert_persisted_policy_element(src, dst)
      src.children << dst
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
    # Disconnect two policy elements in the machine
    # The two policy elements must be persisted policy elements; otherwise the method should raise
    # an ArgumentError.
    # Returns true if unassignment occurred and false otherwise.
    # Generally, false will be returned if the assignment didn't exist in the PM in the
    # first place.
    #
    def unassign(src, dst)
      assert_persisted_policy_element(src, dst)
      if assignment = src.assignments.where(child_id: dst.id).first
        assignment.destroy
      end
    end

    ##
    # Remove a persisted policy element. This should remove its assignments and
    # associations but must not cascade to any connected policy elements.
    # Returns true if the delete succeeded.
    #
    def delete(element)
      element.destroy
    end

    ##
    # Update the extra_attributes of a persisted policy element.
    # This should only affect attributes corresponding to the keys passed in.
    # Returns true if the update succeeded or was redundant.
    #
    def update(element, changes_hash)
      changes_hash.each { |k,v| element.send("#{k}=",v) }
      element.save
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
    def add_association(user_attribute, operation_set, object_attribute, policy_machine_uuid)
      PolicyElementAssociation.where(
        user_attribute_id: user_attribute.id,
        object_attribute_id: object_attribute.id
      ).first_or_create.operations = operation_set.to_a
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
      assocs = operation.policy_element_associations.all(include: [:user_attribute, :operations, :object_attribute])
      assocs.map { |assoc| [assoc.user_attribute, Set.new(assoc.operations), assoc.object_attribute] }
    end

    ##
    # Return array of all policy classes which contain the given object_attribute (or object).
    # Return empty array if no such policy classes found.
    def policy_classes_for_object_attribute(object_attribute)
      object_attribute.descendants.where(type: class_for_type('policy_class'))
    end

    ##
    # Return array of all user attributes which contain the given user.
    # Return empty array if no such user attributes are found.
    def user_attributes_for_user(user)
      user.descendants.where(type: class_for_type('user_attribute'))
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
      if policy_classes_containing_object.count < 2
        is_privilege_single_policy_class(user_or_attribute, operation, object_or_attribute)
      else
        is_privilege_multiple_policy_classes(user_or_attribute, operation, object_or_attribute, policy_classes_containing_object)
      end
    end

    ## Optimized version of PolicyMachine#scoped_privileges
    # Returns all operations the user has on the object
    def scoped_privileges(user_or_attribute, object_or_attribute)
      policy_classes_containing_object = policy_classes_for_object_attribute(object_or_attribute)
      if policy_classes_containing_object.count < 2
        scoped_privileges_single_policy_class(user_or_attribute, object_or_attribute)
      else
        scoped_privileges_multiple_policy_classes(user_or_attribute, object_or_attribute, policy_classes_containing_object)
      end
    end

    private

    def is_privilege_single_policy_class(user_or_attribute, operation, object_or_attribute)
      if operation.is_a?(class_for_type('operation'))
        associations_between(user_or_attribute, object_or_attribute).where(id: operation.policy_element_associations).any?
      else
        associations_between(user_or_attribute, object_or_attribute).joins(:operations).where(policy_elements: {unique_identifier: operation}).any?
      end
    end

    def is_privilege_multiple_policy_classes(user_or_attribute, operation, object_or_attribute, policy_classes_containing_object)
      base_scope =  if operation.is_a?(class_for_type('operation'))
        associations_between(user_or_attribute, object_or_attribute).where(id: operation.policy_element_associations)
      else
        associations_between(user_or_attribute, object_or_attribute).joins(:operations).where(policy_elements: {unique_identifier: operation})
      end
      policy_classes_containing_object.all? do |pc|
        base_scope.where(object_attribute_id: pc.ancestors).any?
      end
    end

    def scoped_privileges_single_policy_class(user_or_attribute, object_or_attribute)
      associations = associations_between(user_or_attribute, object_or_attribute).includes(:operations)
      associations.flat_map(&:operations).uniq
    end

    def scoped_privileges_multiple_policy_classes(user_or_attribute, object_or_attribute, policy_classes_containing_object)
      base_scope = associations_between(user_or_attribute, object_or_attribute)
      operations_for_policy_classes = policy_classes_containing_object.map do |pc|
        associations = base_scope.where(object_attribute_id: pc.ancestors).includes(:operations)
        associations.flat_map(&:operations)
      end
      operations_for_policy_classes.inject(:&) || []
    end

    def associations_between(user_or_attribute, object_or_attribute)
      class_for_type('policy_element_association').where(
        object_attribute_id: object_or_attribute.descendants | [object_or_attribute],
        user_attribute_id: user_or_attribute.descendants | [user_or_attribute]
      )
    end

    def assert_persisted_policy_element(*arguments)
      arguments.each do |argument|
        raise ArgumentError, "expected policy elements, got #{argument}" unless argument.is_a?(PolicyElement)
      end
    end

  end
end unless active_record_unavailable
