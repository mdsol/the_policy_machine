begin
  require 'neography'
rescue LoadError
  neography_unavailable = true
end

# This class stores policy elements in a neo4j graph db using the neography client and 
# exposes required operations for managing/querying these elements.
# Note that this adapter shouldn't be used in production for high-performance needs as Neography
# is inherently slower than more direct NEO4J access.
module PolicyMachineStorageAdapter
  class Neography
    
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
        node_attrs = {
          :unique_identifier => unique_identifier,
          :policy_machine_uuid => policy_machine_uuid,
          :pe_type => pe_type,
          :persisted => true
        }.merge(extra_attributes)
        persisted_pe = ::Neography::Node.create(node_attrs)
        persisted_pe.add_to_index('nodes', 'unique_identifier', unique_identifier)
        persisted_pe.add_to_index('policy_element_types', 'pe_type', pe_type)
        persisted_pe
      end
      
      define_method("find_all_of_type_#{pe_type}") do |options = {}|
        found_elts = ::Neography::Node.find('policy_element_types', 'pe_type', pe_type)
        found_elts = found_elts.nil? ? [] : [found_elts].flatten
        found_elts.select do |elt|
          options.all? do |k,v|
            if v.nil?
              !elt.respond_to?(k)
            else
              elt.respond_to?(k) && elt.send(k) == v
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
      
      e = ::Neography::Relationship.create(:outgoing, src, dst)
      
      if e.nil?
        false
      else
        unique_identifier = src.unique_identifier + dst.unique_identifier
        e.add_to_index('edges', 'unique_identifier', unique_identifier)
        true
      end
    end
    
    ##
    # Determine if there is a path from src to dst in the policy machine
    #
    def connected?(src, dst)
      assert_persisted_policy_element(src)
      assert_persisted_policy_element(dst)
      
      return true if src == dst
      
      neo_connection.execute_query("start n=node({id1}),m=node({id2}) return (n)-[*]->(m)", 
        {:id1 => src.neo_id.to_i, :id2 => dst.neo_id.to_i})['data'] != [[[]]]
    end

    ##
    # Disconnect two policy elements in the machine
    #    
    def unassign(src, dst)
      assert_persisted_policy_element(src)
      assert_persisted_policy_element(dst)
      
      unique_identifier = src.unique_identifier + dst.unique_identifier
      found_edges = ::Neography::Relationship.find('edges', 'unique_identifier', unique_identifier)
      
      if found_edges
        # Neography::Relationship doesn't respond to .to_a
        found_edges = [found_edges] unless found_edges.is_a?(Array)
        found_edges.each do |found_edge|
          # Unfortunately, we have to reload the edge as find isn't deserializing it properly.
          e = ::Neography::Relationship.load(found_edge.neo_id.to_i)
          e.del unless e.nil?
        end
        true
      else
        false
      end
    end

    ##
    # Remove a persisted policy element
    #
    def delete(element)
      if %w[user_attribute object_attribute].include?(element.pe_type)
        element.outgoing(:in_association).each do |assoc|
          assoc.del
        end
      end
      element.del
    end

    ##
    # Update a persisted policy element
    #
    def update(element, changes_hash)
      element.neo_server.set_node_properties(element.neo_id, changes_hash)
    end

    
    ##
    # Determine if the given node is in the policy machine or not.
    def element_in_machine?(pe)
      found_node = ::Neography::Node.find('nodes', 'unique_identifier', pe.unique_identifier)
      !found_node.nil?
    end
    
    ##
    # Add the given association to the policy map.  If an association between user_attribute
    # and object_attribute already exists, then replace it with that given in the arguments.
    def add_association(user_attribute, operation_set, object_attribute, policy_machine_uuid)
      remove_association(user_attribute, object_attribute, policy_machine_uuid)
      
      # TODO:  scope by policy machine uuid
      unique_identifier = user_attribute.unique_identifier + object_attribute.unique_identifier
      node_attrs = {
        :unique_identifier => unique_identifier,
        :policy_machine_uuid => policy_machine_uuid,
        :user_attribute_unique_identifier => user_attribute.unique_identifier,
        :object_attribute_unique_identifier => object_attribute.unique_identifier,
        :operations => operation_set.map(&:unique_identifier).to_json,
      }
      persisted_assoc = ::Neography::Node.create(node_attrs)
      persisted_assoc.add_to_index('associations', 'unique_identifier', unique_identifier)
      
      [user_attribute, object_attribute, *operation_set].each do |element|
        ::Neography::Relationship.create(:in_association, element, persisted_assoc)
      end

      true
    end
    
    ##
    # Return all associations in which the given operation is included
    # Returns an array of arrays.  Each sub-array is of the form
    # [user_attribute, operation_set, object_attribute]
    #
    def associations_with(operation)
      operation.outgoing(:in_association).map do |association|
        user_attribute = ::Neography::Node.find('nodes', 'unique_identifier', association.user_attribute_unique_identifier)
        object_attribute = ::Neography::Node.find('nodes', 'unique_identifier', association.object_attribute_unique_identifier)
        
        operation_set = Set.new
        JSON.parse(association.operations).each do |op_unique_id|
          op_node = ::Neography::Node.find('nodes', 'unique_identifier', op_unique_id)
          operation_set << op_node
        end
        
        [user_attribute, operation_set, object_attribute]
      end      
    end
    
    ##
    # Remove an existing association.  Return true if the association was removed and false if 
    # it didn't exist in the first place.
    def remove_association(user_attribute, object_attribute, policy_machine_uuid)
      unique_identifier = user_attribute.unique_identifier + object_attribute.unique_identifier
      
      begin
        assoc_node = ::Neography::Node.find('associations', 'unique_identifier', unique_identifier)
        return false unless assoc_node
        assoc_node.del
        true
      rescue ::Neography::NotFoundException
        false
      end
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
      #Don't use this kind of query plan in a for-production adapter.
      find_all_of_type_user_attribute.select do |user_attribute|
        connected?(user, user_attribute)
      end
    end

    ##
    # Execute the passed-in block transactionally: any error raised out of the block causes
    # all the block's changes to be rolled back.
    def transaction
      raise NotImplementedError, "transactions are only available in neo4j 2.0 which #{self.class} is not compatible with"
    end

    private
    
      # Raise argument error if argument is not suitable for consumption in
      # public methods.
      def assert_persisted_policy_element(arg)
        raise(ArgumentError, "arg must be a Neography::Node; got #{arg.class.name}") unless arg.is_a?(::Neography::Node)
        raise(ArgumentError, "arg must be persisted") unless element_in_machine?(arg)
      end
      
      # Neo4j client
      def neo_connection
        @neo_connection ||= ::Neography::Rest.new
      end
  end
end unless neography_unavailable
