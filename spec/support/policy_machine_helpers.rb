# This file contains helper methods to test assertions on policy machines

# Make sure each expected privilege has been returned
def assert_pm_privilege_expectations(actual_privileges, expected_privileges)
  expected_privileges.each do |ep|
    u_id = ep[0].unique_identifier
    op_id = ep[1].unique_identifier
    obj_id = ep[2].unique_identifier

    found_actual_priv = actual_privileges.find do |priv|
      priv[0].unique_identifier == u_id &&
      priv[1].unique_identifier == op_id &&
      priv[2].unique_identifier == obj_id
    end

    pp("expected to find #{[u_id, op_id, obj_id]}") if found_actual_priv.nil?

    expect(found_actual_priv).to_not be_nil
  end
  expect(actual_privileges.count).to eq(expected_privileges.size)
  assert_pm_scoped_privilege_expectations
end

# Make sure all scoped_privileges calls behave as expected
def assert_pm_scoped_privilege_expectations
  users_or_attributes = policy_machine.users | policy_machine.user_attributes
  objects_or_attributes = policy_machine.objects | policy_machine.object_attributes
  users_or_attributes.product(objects_or_attributes) do |u, o|
    expected_scoped_privileges = policy_machine.operations.reject(&:prohibition?).grep(->op{policy_machine.is_privilege?(u, op.unique_identifier, o)}) do |op|
      [u, op, o]
    end
    expect(policy_machine.scoped_privileges(u,o)).to match_array(expected_scoped_privileges)
  end

end
