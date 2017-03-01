module PM

  # A generic policy element in a policy machine.
  # A policy element can be a user, user attribute, object, object attribute
  # or operation set.
  # This is an abstract base class and should not itself be instantiated.
  class PolicyElement
    attr_accessor   :unique_identifier
    attr_accessor   :policy_machine_uuid
    attr_accessor   :stored_pe
    attr_accessor   :extra_attributes
    attr_reader     :pm_storage_adapter

    # Creates a new policy element with the given name and type.
    def initialize(unique_identifier, policy_machine_uuid, pm_storage_adapter, stored_pe = nil, extra_attributes = {})
      @unique_identifier = unique_identifier.to_s
      @policy_machine_uuid = policy_machine_uuid.to_s
      @pm_storage_adapter = pm_storage_adapter
      @stored_pe = stored_pe
      @extra_attributes = extra_attributes
    end

    # Determines if self is connected to other node
    def connected?(other_pe)
      pm_storage_adapter.connected?(self.stored_pe, other_pe.stored_pe)
    end

    # Determines if self is a logical link to other node
    def linked?(other_pe)
      pm_storage_adapter.linked?(self.stored_pe, other_pe.stored_pe)
    end

    # Assigns self to destination policy element
    # This method is sensitive to the type of self and dst_policy_element
    def assign_to(dst_policy_element)
      unless allowed_assignee_classes.any?{|aac| dst_policy_element.is_a?(aac)}
        raise(ArgumentError, "expected dst_policy_element to be one of #{allowed_assignee_classes.to_s}; got #{dst_policy_element.class} instead.")
      end

      pm_storage_adapter.assign(self.stored_pe, dst_policy_element.stored_pe)
    end

    # Assigns self to destination policy element in a different policy machine
    # This is used for logical relationships outside of the policy machine formalism, such as the
    # relationship between a class of operable and a specific instance of it.
    def link_to(dst_policy_element)
      pm_storage_adapter.link(self.stored_pe, dst_policy_element.stored_pe)
    end

    # Removes an assignment from self to destination policy element where the
    # destination policy element is in a different policy machine.
    # Returns boolean indicating whether assignment was successfully removed.
    # This is used for logical relationships outside of the policy machine formalism, such as the
    # relationship between a class of operable and a specific instance of it.
    def unlink(dst_policy_element)
      pm_storage_adapter.unlink(self.stored_pe, dst_policy_element.stored_pe)
    end

    # Removes assignment from self to destination policy element
    # Returns boolean indicating whether assignment was successfully removed.
    def unassign(dst_policy_element)
      pm_storage_adapter.unassign(self.stored_pe, dst_policy_element.stored_pe)
    end

    # Removes self and any assignments to or from self. Does not remove any other elements.
    # Returns true if persisted object was successfully removed.
    def delete
      if self.stored_pe && self.stored_pe.persisted
        pm_storage_adapter.delete(stored_pe)
        self.stored_pe = nil
        true
      end
    end

    # Updates extra attributes with the passed-in values. Will not remove other
    # attributes not in the hash. Returns true if no errors occurred.
    def update(attr_hash)
      @extra_attributes.merge!(attr_hash)
      #TODO: consider removing the persisted check to allow for buffered writes
      if self.stored_pe && self.stored_pe.persisted
        pm_storage_adapter.update(self.stored_pe, attr_hash)
        true
      end
    end

    # Converts a stored_pe to an instantiated pe
    def self.convert_stored_pe_to_pe(stored_pe, pm_storage_adapter, pe_class = self)
      pe_class.new(
        stored_pe.unique_identifier,
        stored_pe.policy_machine_uuid,
        pm_storage_adapter,
        stored_pe
      )
    end

    # Returns true if self is identical to other and false otherwise.
    def ==(other_pe)
      self.class == other_pe.class &&
      self.unique_identifier == other_pe.unique_identifier &&
      self.policy_machine_uuid == other_pe.policy_machine_uuid
    end

    # Delegates extra attribute reads to stored_pe
    def method_missing(meth, *args)
      if args.none? && stored_pe.respond_to?(meth)
        stored_pe.send(meth)
      else
        super
      end
    end

    def respond_to_missing?(meth, include_private = false)
      stored_pe.respond_to?(meth, include_private) || super
    end

    def inspect
      "#<#{self.class} #{unique_identifier}>"
    end

    protected

    def allowed_assignee_classes
      raise "Must override this method in a subclass"
    end

    def self.create(unique_identifier, policy_machine_uuid, pm_storage_adapter, extra_attributes = {})
      new_pe = new(unique_identifier, policy_machine_uuid, pm_storage_adapter, nil, extra_attributes)
      method_name = "add_#{self.name.split('::').last}".underscore.to_sym
      new_pe.stored_pe = pm_storage_adapter.send(method_name, unique_identifier, policy_machine_uuid, extra_attributes)
      new_pe
    end

    # Returns all policy elements of a particular type (e.g. all users)
    # TODO: Move all overrides of self.all to the base class
    def self.all(pm_storage_adapter, options = {})
      method_name = "find_all_of_type_#{self.name.split('::').last}".underscore.to_sym
      result = pm_storage_adapter.send(method_name, options)
      all_result = result.map do |stored_pe|
        convert_stored_pe_to_pe(stored_pe, pm_storage_adapter, self)
      end
      all_result.define_singleton_method(:total_entries) { result.total_entries }
      all_result
    end

  end

  # A user in a policy machine.
  class User < PolicyElement
    def user_attributes(pm_storage_adapter)
      pm_storage_adapter.user_attributes_for_user(stored_pe).map do |stored_ua|
        self.class.convert_stored_pe_to_pe(stored_ua, pm_storage_adapter, PM::UserAttribute)
      end
    end

    protected
    def allowed_assignee_classes
      [UserAttribute]
    end
  end

  # A user attribute in a policy machine.
  class UserAttribute < PolicyElement

    protected
    def allowed_assignee_classes
      [UserAttribute, PolicyClass]
    end
  end

  # An object attribute in a policy machine.
  class ObjectAttribute < PolicyElement
    # Returns an array of policy classes in which this ObjectAttribute is included.
    # Returns empty array if this ObjectAttribute is associated with no policy classes.
    def policy_classes
      pcs_for_object = pm_storage_adapter.policy_classes_for_object_attribute(stored_pe)
      pcs_for_object.map do |stored_pc|
        self.class.convert_stored_pe_to_pe(stored_pc, pm_storage_adapter, PM::PolicyClass)
      end
    end

    protected
    def allowed_assignee_classes
      [ObjectAttribute, PolicyClass]
    end
  end

  # An object in a policy machine.
  class Object < ObjectAttribute

    protected
    def allowed_assignee_classes
      [Object, ObjectAttribute]
    end
  end

  # An operation in a policy machine.
  class Operation < PolicyElement
    def self.create(unique_identifier, policy_machine_uuid, pm_storage_adapter, extra_attributes = {}, prohibition = false)
      if unique_identifier =~ /^~/ && !prohibition
        raise ArgumentError, "A non-prohibition operation cannot start with '~'"
      end
      new_pe = new(unique_identifier, policy_machine_uuid, pm_storage_adapter, nil, extra_attributes)
      new_pe.stored_pe = pm_storage_adapter.add_operation(unique_identifier, policy_machine_uuid, extra_attributes)
      new_pe
    end

    def self.find_or_create(unique_identifier, policy_machine_uuid, pm_storage_adapter, extra_attributes = {}, prohibition = false)
      op = pm_storage_adapter.find_all_of_type_operation(unique_identifier: unique_identifier, policy_machine_uuid: policy_machine_uuid).first
      if op
        convert_stored_pe_to_pe(op, pm_storage_adapter, self)
      else
        create(unique_identifier, policy_machine_uuid, pm_storage_adapter, extra_attributes = {}, prohibition)
      end
    end

    def to_s
      unique_identifier
    end

    def operation
      unique_identifier.sub(/^~/,'')
    end

    def prohibition
      Prohibition.on(self)
    end

    def prohibition?
      unique_identifier =~ /^~/
    end

    # Return all associations in which this Operation is included
    # Associations are arrays of PM::Attributes.
    def associations
      pm_storage_adapter.associations_with(self.stored_pe).map do |assoc|
        PM::Association.new(assoc[0], assoc[1], assoc[2], pm_storage_adapter)
      end
    end

    protected
    def allowed_assignee_classes
      []
    end
  end

  # A prohibition in a policy machine.
  class Prohibition < PolicyElement
    def self.on(operation)
      negation = "~#{operation}"
      case operation
      when PM::Operation
        PM::Operation.find_or_create(negation,operation.policy_machine_uuid, operation.pm_storage_adapter, {}, true)
      when Symbol
        negation.to_sym
      when String
        negation
      else
        raise(ArgumentError, "operation must be an Operation, Symbol, or String.")
      end
    end
  end

  # A policy class in a policy machine.
  class PolicyClass < PolicyElement
    protected
    def allowed_assignee_classes
      []
    end
  end

end
