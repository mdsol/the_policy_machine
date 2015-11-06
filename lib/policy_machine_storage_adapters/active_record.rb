require 'policy_machine'
require 'set'

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

    # Load the Assignment and Adapter classes at runtime because it's implemented differently by different adapters
    # And which database adapter is active is not always determinable at class definition time
    # Assignment must inherit from ActiveRecord::Base and have class methods ancestors_of, descendants_of, and transitive_closure?
    # Adapter must implement apply_include_condition
    def self.const_missing(name)
      if %w[Assignment Adapter].include?(name.to_s)
        load_db_adapter!
        const_get(name)
      else
        super
      end
    end

    def self.load_db_adapter!
      require_relative("active_record/#{PolicyElement.configurations[Rails.env]['adapter']}")
    end

    class PolicyElement < ::ActiveRecord::Base
      alias :persisted :persisted?
      # needs unique_identifier, policy_machine_uuid, type, extra_attributes columns
      has_many :assignments, foreign_key: :parent_id, dependent: :destroy
      has_many :children, through: :assignments, dependent: :destroy #this doesn't actually destroy the children, just the assignment

      attr_accessor :extra_attributes_hash

      serialize :extra_attributes, JSON

      def method_missing(meth, *args, &block)
        store_attributes
        if respond_to?(meth)
          send(meth, *args)
        elsif meth.to_s[-1] == '='
          @extra_attributes_hash[meth.to_s] = args.first
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
        @extra_attributes_hash = extra_attributes
        self.class.store_accessor(:extra_attributes, @extra_attributes_hash.keys)
      end

      def descendants
        Assignment.descendants_of(self)
      end

      def ancestors
        Assignment.ancestors_of(self)
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
      has_and_belongs_to_many :policy_element_associations, class_name: 'PolicyMachineStorageAdapter::ActiveRecord::PolicyElementAssociation', join_table: 'operations_policy_element_associations'
    end

    class PolicyClass < PolicyElement
    end

    class PolicyElementAssociation < ::ActiveRecord::Base
      # requires a join table (should be indexed!)
      has_and_belongs_to_many :operations, class_name: "PolicyMachineStorageAdapter::ActiveRecord::Operation", join_table: 'operations_policy_element_associations'

      belongs_to :user_attribute
      belongs_to :object_attribute

      #TODO: ActiveRecord's generated operations= method is inefficient, makes 1 query for each op added or removed even though there's no hooks
      # Awkward manual implementation for now, but in the future change this to an hstore or something in the postgres adapter,
      # and/or fix Rails.
      def operations=(updated_operations)
        updated_operation_set = Set.new(updated_operations)
        current_operation_set = Set.new(self.operations)
        new_operations = updated_operation_set - current_operation_set
        removed_operations = current_operation_set - updated_operation_set
        transaction do
          OperationsPolicyElementAssociation.where(policy_element_association_id: self.id)
                                            .where(operation_id: removed_operations.map(&:id))
                                            .delete_all
          OperationsPolicyElementAssociation.import([:policy_element_association_id, :operation_id],
                                                     new_operations.map{ |op| [self.id, op.id] },
                                                     validate: false)
        end
        self.clear_association_cache
      end
    end

    class OperationsPolicyElementAssociation < ::ActiveRecord::Base
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
          :extra_attributes => extra_attributes
        }.merge(active_record_attributes)
        class_for_type(pe_type).create(element_attrs)
      end

      define_method("find_all_of_type_#{pe_type}") do |options = {}|
        conditions = options.slice!(:per_page, :page, :ignore_case).stringify_keys
        extra_attribute_conditions = conditions.slice!(*PolicyElement.column_names)
        include_conditions, conditions = conditions.partition { |k,v| include_condition?(k,v) }
        pe_class = class_for_type(pe_type)

        # Arel matches provides agnostic case insensitive sql for mysql and postgres
        all = begin
          if options[:ignore_case]
            match_expressions = conditions.map {|k,v| ignore_case_applies?(options[:ignore_case],k) ?
              pe_class.arel_table[k].matches(v) : pe_class.arel_table[k].eq(v) }
            match_expressions.inject(pe_class.where(nil)) {|rel, e| rel.where(e)}
          else
            pe_class.where(conditions.to_h)
          end
        end

        include_conditions.each do |key, value|
          all = Adapter.apply_include_condition(scope: all, key: key, value: value[:include], klass: class_for_type(pe_type))
        end

        extra_attribute_conditions.each do |key, value|
          warn "WARNING: #{self.class} is filtering #{pe_type} on #{key} in memory, which won't scale well. " <<
            "To move this query to the database, add a '#{key}' column to the policy_elements table " <<
            "and re-save existing records"
            all.to_a.select!{ |pe| pe.store_attributes and
                        ((attr_value = pe.extra_attributes_hash[key]).is_a?(String) and
                        value.is_a?(String) and ignore_case_applies?(options[:ignore_case],key)) ? attr_value.downcase == value.downcase : attr_value == value}
        end
        # Default to first page if not specified
        if options[:per_page]
          page = options[:page] ? options[:page] : 1
          all = all.order(:id).paginate(page: page, per_page: options[:per_page])
        end

        # TODO: Look into moving this block into previous pagination conditional and test in consuming app
        unless all.respond_to? :total_entries
          all.define_singleton_method(:total_entries) do
            all.count
          end
        end
        all
      end
    end

    # Allow ignore_case to be a boolean, string, symbol, or array of symbols or strings
    def ignore_case_applies?(ignore_case, key)
      return false if key == 'policy_machine_uuid'
      ignore_case == true || ignore_case.to_s == key || ( ignore_case.respond_to?(:any?) && ignore_case.any?{ |k| k.to_s == key} )
    end

    # A value hash where the only key is :include is special.
    #Note: If we start accepting literal hash values this may need to start checking the key's column type
    def include_condition?(key, value)
      value.respond_to?(:keys) && value.keys == [:include]
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
      Assignment.where(parent_id: src.id, child_id: dst.id).first_or_create
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

      assocs = operation.policy_element_associations(true).includes(:user_attribute, :operations, :object_attribute).all
      assocs.map do |assoc|
        assoc.clear_association_cache #TODO Either do this better (touch through HABTM on bulk insert?) or dont do this?
        [assoc.user_attribute, Set.new(assoc.operations), assoc.object_attribute]
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
      if policy_classes_containing_object.count < 2
        is_privilege_single_policy_class(user_or_attribute, operation, object_or_attribute)
      else
        is_privilege_multiple_policy_classes(user_or_attribute, operation, object_or_attribute, policy_classes_containing_object)
      end
    end

    ## Optimized version of PolicyMachine#scoped_privileges
    # Returns all operations the user has on the object
    def scoped_privileges(user_or_attribute, object_or_attribute, options = {})
      policy_classes_containing_object = policy_classes_for_object_attribute(object_or_attribute)
      if policy_classes_containing_object.count < 2
        scoped_privileges_single_policy_class(user_or_attribute, object_or_attribute, options)
      else
        scoped_privileges_multiple_policy_classes(user_or_attribute, object_or_attribute, policy_classes_containing_object, options)
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
      #Outstanding active record sql adapter prevents chaining an additional where using the association.
      # TODO: fix when active record is fixed
      policy_classes_containing_object.all? do |pc|
        if operation.is_a?(class_for_type('operation'))
          associations_between(user_or_attribute, object_or_attribute).where(id: operation.policy_element_associations.to_a, object_attribute_id: pc.ancestors).any?
        else
          associations_between(user_or_attribute, object_or_attribute).joins(:operations).where(policy_elements: {unique_identifier: operation}, object_attribute_id: pc.ancestors).any?
        end
      end
    end

    # Pass in options to allow forced row ordering by id in results
    def scoped_privileges_single_policy_class(user_or_attribute, object_or_attribute, options = {})
      associations = associations_between(user_or_attribute, object_or_attribute).includes(:operations)
      operations = associations.flat_map do |assoc|
        assoc.clear_association_cache
        assoc.operations
      end.uniq
      options[:order] ? operations.sort : operations
    end

    def scoped_privileges_multiple_policy_classes(user_or_attribute, object_or_attribute, policy_classes_containing_object, options = {})
      base_scope = associations_between(user_or_attribute, object_or_attribute)
      operations_for_policy_classes = policy_classes_containing_object.map do |pc|
        associations = base_scope.where(object_attribute_id: pc.ancestors).includes(:operations)
        associations.flat_map do |assoc|
          assoc.clear_association_cache
          assoc.operations
        end.uniq
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
