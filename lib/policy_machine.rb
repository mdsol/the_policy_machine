require 'policy_machine/policy_element'
require 'policy_machine/association'
require 'securerandom'
require 'active_support/inflector'
require 'set'
require 'will_paginate/array'

# require all adapters
Dir.glob(File.dirname(File.absolute_path(__FILE__)) + '/policy_machine_storage_adapters/*.rb').each{ |f| require f }

class PolicyMachine
  POLICY_ELEMENT_TYPES = %w(user user_attribute object object_attribute operation policy_class)

  attr_accessor :name
  attr_reader   :uuid
  attr_reader   :policy_machine_storage_adapter

  def initialize(options = {})
    @name = (options[:name] || options['name'] || 'default_policy_machine').to_s.strip
    @uuid = (options[:uuid] || options['uuid'] || SecureRandom.uuid).to_s.strip
    policy_machine_storage_adapter_class = options[:storage_adapter] || options['storage_adapter'] || ::PolicyMachineStorageAdapter::InMemory
    @policy_machine_storage_adapter = policy_machine_storage_adapter_class.new

    raise(ArgumentError, "uuid cannot be blank") if @uuid.empty?
  end

  ##
  # Persist an assignment in this policy machine.
  # An assignment is a binary relation between two existing policy elements.
  # Some policy element types cannot be assigned to other types.  See the NIST
  # spec for details.
  #
  def add_assignment(src_policy_element, dst_policy_element)
    assert_policy_element_in_machine(src_policy_element)
    assert_policy_element_in_machine(dst_policy_element)

    src_policy_element.assign_to(dst_policy_element)
  end

  ##
  # Remove an assignment in this policy machine.
  #
  def remove_assignment(src_policy_element, dst_policy_element)
    assert_policy_element_in_machine(src_policy_element)
    assert_policy_element_in_machine(dst_policy_element)

    src_policy_element.unassign(dst_policy_element)
  end

  ##
  # Add an association between a user_attribute, an operation_set and an object_attribute
  # in this policy machine.
  #
  def add_association(user_attribute_pe, operation_set, object_attribute_pe)
    assert_policy_element_in_machine(user_attribute_pe)
    operation_set.each{ |op| assert_policy_element_in_machine(op) }
    assert_policy_element_in_machine(object_attribute_pe)

    PM::Association.create(user_attribute_pe, operation_set, object_attribute_pe, @uuid, @policy_machine_storage_adapter)
  end

  ##
  # Can we derive a privilege of the form (u, op, o) from this policy machine?
  # user_or_attribute is a user or user_attribute.
  # operation is an operation.
  # object_or_attribute is an object or object attribute.
  #
  # TODO: add option to ignore policy classes to allow consumer to speed up this method.
  # TODO: Parallelize the two component checks
  def is_privilege?(user_or_attribute, operation, object_or_attribute, options = {})
    is_privilege_ignoring_prohibitions?(user_or_attribute, operation, object_or_attribute, options) &&
      !is_privilege_ignoring_prohibitions?(user_or_attribute, PM::Prohibition.on(operation), object_or_attribute, options)
  end

  ##
  # Check the privilege without checking for prohibitions. May be called directly but is also used in is_privilege?
  #
  def is_privilege_ignoring_prohibitions?(user_or_attribute, operation, object_or_attribute, options = {})
    unless user_or_attribute.is_a?(PM::User) || user_or_attribute.is_a?(PM::UserAttribute)
      raise(ArgumentError, "user_attribute_pe must be a User or UserAttribute.")
    end

    unless [PM::Operation, Symbol, String].any? { |allowed_type| operation.is_a?(allowed_type) }
      raise(ArgumentError, "operation must be an Operation, Symbol, or String.")
    end

    unless object_or_attribute.is_a?(PM::Object) || object_or_attribute.is_a?(PM::ObjectAttribute)
      raise(ArgumentError, "object_or_attribute must either be an Object or ObjectAttribute.")
    end

    if options.empty? && policy_machine_storage_adapter.respond_to?(:is_privilege?)
      privilege = [user_or_attribute, operation, object_or_attribute].map { |obj| obj.respond_to?(:stored_pe) ? obj.stored_pe : obj }
      return policy_machine_storage_adapter.is_privilege?(*privilege)
    end

    unless operation.is_a?(PM::Operation)
      operation = operations(unique_identifier: operation.to_s).first or return false
    end

    # Try to get associations to check from options
    associations = options[:associations] || options['associations']
    if associations
      raise(ArgumentError, "expected options[:associations] to be an Array; got #{associations.class}") unless associations.is_a?(Array)
      raise(ArgumentError, "options[:associations] cannot be empty") if associations.empty?
      raise(ArgumentError, "expected each element of options[:associations] to be a PM::Association") unless associations.all?{|a| a.is_a?(PM::Association)}

      associations.keep_if{ |assoc| assoc.includes_operation?(operation) }
      return false if associations.empty?
    else
      associations = operation.associations
    end

    # Is a privilege iff options[:in_user_attribute] is involved (given options[:in_user_attribute] is not nil)
    in_user_attribute = options[:in_user_attribute] || options['in_user_attribute']
    if in_user_attribute
      unless in_user_attribute.is_a?(PM::UserAttribute)
        raise(ArgumentError, "expected options[:in_user_attribute] to be a PM::UserAttribute; got #{in_user_attribute.class}")
      end
      if user_or_attribute.connected?(in_user_attribute)
        user_or_attribute = in_user_attribute
      else
        return false
      end
    end

    # Is a privilege iff options[:in_object_attribute] is involved (given options[:in_object_attribute] is not nil)
    in_object_attribute = options[:in_object_attribute] || options['in_object_attribute']
    if in_object_attribute
      unless in_object_attribute.is_a?(PM::ObjectAttribute)
        raise(ArgumentError, "expected options[:in_object_attribute] to be a PM::ObjectAttribute; got #{in_object_attribute.class}")
      end
      if object_or_attribute.connected?(in_object_attribute)
        object_or_attribute = in_object_attribute
      else
        return false
      end
    end

    policy_classes_containing_object = object_or_attribute.policy_classes
    if policy_classes_containing_object.empty?
      is_privilege_single_policy_class(user_or_attribute, object_or_attribute, associations)
    else
      is_privilege_multiple_policy_classes(user_or_attribute, object_or_attribute, associations, policy_classes_containing_object)
    end
  end

  

  ##
  # Returns an array of all privileges encoded in this
  # policy machine.  Each privilege is of the form:
  # [PM::User, PM::Operation, PM::Object]
  #
  # TODO:  might make privilege a class of its own
  def privileges
    privileges = []

    users.each do |user|
      operations.reject(&:prohibition?).each do |operation|
        objects.each do |object|
          if is_privilege?(user, operation, object)
            privileges << [user, operation, object]
          end
        end
      end
    end

    privileges
  end

  ##
  # Returns an array of all privileges encoded in this
  # policy machine for the given user (attribute) on the given
  # object (attribute).
  #
  # TODO:  might make privilege a class of its own
  def scoped_privileges(user_or_attribute, object_or_attribute, options = {})
    privileges_and_prohibitions = if policy_machine_storage_adapter.respond_to?(:scoped_privileges)
      policy_machine_storage_adapter.scoped_privileges(user_or_attribute.stored_pe, object_or_attribute.stored_pe, options).map do |op|
        operation = PM::Operation.convert_stored_pe_to_pe(op, policy_machine_storage_adapter, PM::Operation)
        [user_or_attribute, operation, object_or_attribute]
      end
    else
      operations.grep(->operation{is_privilege_ignoring_prohibitions?(user_or_attribute, operation, object_or_attribute)}) do |op|
        [user_or_attribute, op, object_or_attribute]
      end
    end
    prohibitions, privileges = privileges_and_prohibitions.partition { |_,op,_| op.prohibition? }
    if options[:ignore_prohibitions]
      privileges
    else
      prohibited_operations = prohibitions.map { |_,prohibition,_| prohibition.operation }
      privileges.reject { |_,op,_| prohibited_operations.include?(op.unique_identifier) }
    end
  end

  ##
  # Returns an array of all user_attributes a PM::User is assigned to,
  # directly or indirectly.
  def list_user_attributes(user)
    unless user.is_a?(PM::User)
      raise(ArgumentError, "Expected a PM::User, got a #{user.class}")
    end
    assert_policy_element_in_machine(user)
    user.user_attributes(@policy_machine_storage_adapter)
  end

  POLICY_ELEMENT_TYPES.each do |pe_type|
    pm_class = "PM::#{pe_type.camelize}".constantize

    ##
    # Define a create method for each policy element type, as in create_user
    # Each method takes one argument, the unique_identifier of the policy element.
    #
    define_method("create_#{pe_type}") do |unique_identifier, extra_attributes = {}|
      # when creating a policy element, we provide a unique_identifier, the uuid of this policy machine
      # and a policy machine storage adapter to allow us to persist the policy element.
      pm_class.send(:create, unique_identifier, @uuid, @policy_machine_storage_adapter, extra_attributes)
    end

    ##
    # Define an "all" method for each policy element type, as in .users or .object_attributes
    # This will return all persisted of the elements of this type. If an options hash is passed
    # then only elements that match all specified attributes will be returned.
    #
    define_method(pe_type.pluralize) do |options = {}|
      # TODO:  We might want to scope by the uuid of this policy machine in the request to the persistent store, rather than
      # here, after records have already been retrieved.
      # TODO: When the policy machine raises a NoMethoError, we should log a nice message
      # saying that the underlying policy element class doesn't implement 'all'.  Do
      # it when we have a logger, though.
      all_found = pm_class.send(:all, @policy_machine_storage_adapter, options.merge(policy_machine_uuid: uuid))
    end
  end

  ##
  # Execute the passed-in block transactionally: any error raised out of the block causes
  # all the block's changes to be rolled back.
  # TODO: Possibly rescue NotImplementError and warn.
  def transaction(&block)
    policy_machine_storage_adapter.transaction(&block)
  end

  private

    # Raise unless the argument is a policy element.
    def assert_policy_element_in_machine(arg_pe)
      unless arg_pe.is_a?(PM::PolicyElement)
        raise(ArgumentError, "arg must each be a kind of PolicyElement; got #{arg_pe.class.name} instead")
      end
      unless arg_pe.policy_machine_uuid == self.uuid
        raise(ArgumentError, "#{arg_pe.unique_identifier} is not in policy machine with uuid #{self.uuid}")
      end
    end

    # According to the NIST spec:  "the triple (u, op, o) is a privilege, iff there
    # exists an association (ua, ops, oa), such that user u→+ua, op ∈ ops, and o→*oa."
    # Note:  this method assumes that the caller has already checked that the given operation is in the operation_set
    # for all associations provided.
    def is_privilege_single_policy_class(user_or_attribute, object_or_attribute, associations)
      # does there exist an association (ua, ops, oa), such that user u→+ua, op ∈ ops, and o→*oa?
      associations.any? do |assoc|
        user_or_attribute.connected?(assoc.user_attribute) && object_or_attribute.connected?(assoc.object_attribute)
      end
    end

    # According to the NIST spec:  "In multiple policy class situations, the triple (u, op, o) is a PM privilege, iff for
    # each policy class pcl that contains o, there exists an association (uai, opsj, oak),
    # such that user u→+uai, op ∈ opsj, o→*oak, and oak→+pcl."
    # Note:  this method assumes that the caller has already checked that the given operation is in the operation_set
    # for all associations provided.
    def is_privilege_multiple_policy_classes(user_or_attribute, object_or_attribute, associations, policy_classes_containing_object)
      policy_classes_containing_object.all? do |pc|
        associations.any? do |assoc|
          user_or_attribute.connected?(assoc.user_attribute) &&
          object_or_attribute.connected?(assoc.object_attribute) &&
          assoc.object_attribute.connected?(pc)
        end
      end
    end

end
