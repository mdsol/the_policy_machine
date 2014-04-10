require 'policy_machine'

# This class stores policy elements in memory and
# exposes required operations for managing/querying these elements.

module PolicyMachineStorageAdapter
  class InMemory

    POLICY_ELEMENT_TYPES = %w(user user_attribute object object_attribute operation policy_class)

    POLICY_ELEMENT_TYPES.each do |pe_type|
      ##
      # Store a policy element of type pe_type.
      # The unique_identifier identifies the element within the policy machine.
      # The policy_machine_uuid is the uuid of the containing policy machine.
      #
      # TODO:  add optional check to determine if unique_identifier is truly unique within
      # given policy_machine.
      #
      define_method("add_#{pe_type}") do |unique_identifier, policy_machine_uuid, extra_attributes = {}|
        persisted_pe = PersistedPolicyElement.new(unique_identifier, policy_machine_uuid, pe_type, extra_attributes)
        persisted_pe.persisted = true
        policy_elements << persisted_pe
        persisted_pe
      end

      define_method("find_all_of_type_#{pe_type}") do |options = {}|
        conditions = options.slice!(:per_page, :page).merge(pe_type: pe_type)
        policy_elements.paginate(options.slice(:per_page, :page)).select do |pe|
          conditions.all? do |k,v|
            if v.nil?
              !pe.respond_to?(k) || pe.send(k) == nil
            else
              pe.respond_to?(k) && pe.send(k) == v
            end
          end
        end
      end
    end

    ##
    # Assign src to dst in policy machine
    #
    def assign(src, dst)
      assert_persisted_policy_element(src)
      assert_persisted_policy_element(dst)

      assignments << [src, dst]
      true
    end

    ##
    # Determine if there is a path from src to dst in the policy machine
    #
    def connected?(src, dst)
      assert_persisted_policy_element(src)
      assert_persisted_policy_element(dst)

      return true if src == dst

      distances = dijkstra(src, dst)
      distances.nil? ? false : true
    end

    ##
    # Disconnect two policy elements in the machine
    #
    def unassign(src, dst)
      assert_persisted_policy_element(src)
      assert_persisted_policy_element(dst)

      assignment = assignments.find{|assgn| assgn[0] == src && assgn[1] == dst}
      if assignment
        assignments.delete(assignment)
        true
      else
        false
      end
    end

    ##
    # Remove a persisted policy element
    #
    def delete(element)
      assignments.delete_if{ |assgn| assgn.include?(element) }
      associations.delete_if { |_,assoc| assoc.include?(element) }
      policy_elements.delete(element)
    end

    ##
    # Update a persisted policy element
    #
    def update(element, changes_hash)
      element.send(:extra_attributes).merge!(changes_hash)
    end

    ##
    # Determine if the given node is in the policy machine or not.
    def element_in_machine?(pe)
      policy_elements.member?( pe )
    end

    ##
    # Add the given association to the policy map.  If an association between user_attribute
    # and object_attribute already exists, then replace it with that given in the arguments.
    def add_association(user_attribute, operation_set, object_attribute, policy_machine_uuid)
      # TODO:  scope by policy machine uuid
      associations[user_attribute.unique_identifier + object_attribute.unique_identifier] =
        [user_attribute, operation_set, object_attribute]

      true
    end

    ##
    # Return all associations in which the given operation is included
    # Returns an array of arrays.  Each sub-array is of the form
    # [user_attribute, operation_set, object_attribute]
    def associations_with(operation)
      matching = associations.values.select do |assoc|
        assoc[1].include?(operation)
      end

      matching.map{ |m| [m[0], m[1], m[2]] }
    end

    ##
    # Return array of all policy classes which contain the given object_attribute (or object).
    # Return empty array if no such policy classes found.
    def policy_classes_for_object_attribute(object_attribute)
      find_all_of_type_policy_class.select do |pc|
        connected?(object_attribute, pc)
      end
    end

    ##
    # Return array of all user attributes which contain the given user.
    # Return empty array if no such user attributes are found.
    def user_attributes_for_user(user)
      find_all_of_type_user_attribute.select do |user_attribute|
        connected?(user, user_attribute)
      end
    end

    ##
    # Execute the passed-in block transactionally: any error raised out of the block causes
    # all the block's changes to be rolled back.
    def transaction
      old_state = dup
      instance_variables.each do |var|
        value = instance_variable_get(var)

        if (value.respond_to?(:dup))
          old_state.instance_variable_set(var, value.dup)
        end
      end

      begin
        yield
      rescue Exception
        instance_variables.each do |var|
          value = old_state.instance_variable_get(var)
          instance_variable_set(var, value)
        end
        raise
      end
    end


    private

      # Raise argument error if argument is not suitable for consumption in
      # public methods.
      def assert_persisted_policy_element(arg)
        raise(ArgumentError, "arg must be a PersistedPolicyElement; got #{arg.class.name}") unless arg.is_a?(PersistedPolicyElement)
        raise(ArgumentError, "arg must be persisted") unless element_in_machine?(arg)
      end

      # The policy elements in the persisted policy machine.
      def policy_elements
        @policy_elements ||= []
      end

      # The policy element assignments in the persisted policy machine.
      def assignments
        @assignments ||= []
      end

      # All persisted associations
      def associations
        @associations ||= {}
      end

      def dijkstra(src, dst = nil)
        nodes = policy_elements

        distances = {}
        previouses = {}
        nodes.each do |vertex|
          distances[vertex] = nil # Infinity
          previouses[vertex] = nil
        end
        distances[src] = 0
        vertices = nodes.clone
        until vertices.empty?
          nearest_vertex = vertices.inject do |a, b|
            next b unless distances[a]
            next a unless distances[b]
            next a if distances[a] < distances[b]
            b
          end
          break unless distances[nearest_vertex] # Infinity
          if dst and nearest_vertex == dst
            return distances[dst]
          end
          neighbors = neighbors(nearest_vertex)
          neighbors.each do |vertex|
            alt = distances[nearest_vertex] + 1
            if distances[vertex].nil? or alt < distances[vertex]
              distances[vertex] = alt
              previouses[vertices] = nearest_vertex
              # decrease-key v in Q # ???
            end
          end
          vertices.delete nearest_vertex
        end

        return nil
      end

      # Find all nodes which are directly connected to
      # +node+
      def neighbors(pe)
        neighbors = []
        assignments.each do |assignment|
          neighbors.push assignment[1] if assignment[0] == pe
        end
        return neighbors.uniq
      end

      # Class to represent policy elements
      class PersistedPolicyElement
        attr_accessor :persisted
        attr_reader   :unique_identifier, :policy_machine_uuid, :pe_type, :extra_attributes

        # Ensure that attr keys are strings
        def initialize(unique_identifier, policy_machine_uuid, pe_type, extra_attributes)
          @unique_identifier = unique_identifier
          @policy_machine_uuid = policy_machine_uuid
          @pe_type = pe_type
          @persisted = false
          @extra_attributes = extra_attributes
          extra_attributes.each do |key, value|
            define_singleton_method key, lambda {@extra_attributes[key]}
          end
        end

        def ==(other)
          return false unless other.is_a?(PersistedPolicyElement)
          self.unique_identifier == other.unique_identifier &&
            self.policy_machine_uuid == other.policy_machine_uuid &&
            self.pe_type == other.pe_type
        end

    end
  end
end
