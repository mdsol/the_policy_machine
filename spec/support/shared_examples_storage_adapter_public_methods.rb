require 'spec_helper'

shared_examples "a policy machine storage adapter with required public methods" do
  let(:policy_machine_storage_adapter) { described_class.new }

  policy_element_types = ::PolicyMachine::POLICY_ELEMENT_TYPES
  required_public_methods = []
  policy_element_types.each do |pe_type|
    required_public_methods << "add_#{pe_type}"
    required_public_methods << "find_all_of_type_#{pe_type}"
  end
  required_public_methods += %w(assign connected? unassign delete update element_in_machine? add_association associations_with policy_classes_for_object_attribute transaction)

  required_public_methods.each do |req_public_method|
    it "responds to #{req_public_method}" do
      expect(policy_machine_storage_adapter).to respond_to(req_public_method)
    end
  end

end
