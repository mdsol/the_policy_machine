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

    found_actual_priv.should_not be_nil
  end

  actual_privileges.count.should == expected_privileges.size
  assert_pm_scoped_privilege_expectations(expected_privileges)
end

# Make sure all scoped_privileges calls behave as expected
def assert_pm_scoped_privilege_expectations(expected_privileges)
  users = policy_machine.users
  objects = policy_machine.objects
  users.product(objects) do |user, object|
    expected_scoped_privileges = expected_privileges.select do |u,_,o|
      u.unique_identifier == user.unique_identifier &&
      o.unique_identifier ==object.unique_identifier
    end
    policy_machine.scoped_privileges(user,object).should =~ expected_scoped_privileges
  end
end
