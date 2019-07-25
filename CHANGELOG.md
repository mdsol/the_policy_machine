# Changelog

## 2.2.0
* Update .accessible_ancestor_objects to accept an optional associations_with_operation argument.
* Update .accessible_ancestor_objects options argument to require a keyword.

## 2.1.2
* Optimized ActiveRecord adapter for PolicyMachine `#accessible_ancestor_objects`.

## 2.1.1
* Added `include_prohibitions` option to PolicyMachine `#scoped_privileges`.

## 2.1.0
* Elevate associations_filtered_by_operation to a public method in the ActiveRecord storage adapter.

## 2.0.1
* Fix JSON serialization of the `extra_attributes` column.

## 2.0.0
* Upgrade the Policy Machine to support Rails 5.2.

## 1.9.0
* Add `is_privilege_with_filters?` and `is_privilege_ignoring_prohibitions_with_filters?` methods to Policy Machine.
* Add `is_privilege_with_filters?` method to ActiveRecord storage adapter.
* Update `scoped_privileges`, `accessible_objects`, `accessible_ancestor_objects`, and `accessible_operations` to accept a user attribute filter.

## 1.8.1
* Refactor `accessible_ancestor_objects` and `accessible_objects`.

## 1.8.0
* Add accessible_ancestor_objects method to ActiveRecord storage adapter.

## 1.7.4
* Re-expose the 'class_for_type' method to the public interface. 

## 1.7.3
* Improve find_all_of_type_* functionality. This allows for properly passing
  arrays as arguments as well as making the ignore_case parameter work as
  intended.

## 1.7.2
* Loosen 'pg' gem restriction to '< 1.0.0'.

## 1.7.1
* Downversion 'pg' gem to '~> 0.15.0' to avoid v1.0.0 error with core Rails.

## 1.7.0
* Add pluck_ancestor_tree method to ActiveRecord storage adapter.

## 1.6.2
* Add pluck_from method family to the ActiveRecord storage adapter.

## 1.6.1
* Fix a bug in the active record adapter's accessible_objects method preventing it from returing the correct operation set ids.

## 1.6.0
* Give precedence to column attribute accessors instead of extra_attributes during store_attributes memoization.
* Update `is_privilege` and `accessible_objects` to use the assignments join table instead of the operations policy elements associations table.

## 1.5.3
* Add optional filtering to parents and children attribute accessors in the ActiveRecord storage
  adapter.

## 1.5.2
* Upgrade RSpec dependency to version 3.5.0
* Add optional filtering to descendants and ancestors methods in the ActiveRecord storage
  adapter.

## 1.5.1
* Fix a bug in some of the new import code that prevented operation policy
  element associations from saving correctly when encountering duplicates, also
  apply a new partial unique backing index to the policy element associations table

## 1.5.0
* Add an OperationSet element, and make an operation set a new required field for
  creating an Association.  This will be a required field to populate before consuming
  the 2.0 version of the policy machine.

## 1.4.2
* Update the ActiveRecord Adapter to use upserts instead of first or creates for Assignments.

## 1.4.1
* Standardized the return value of batch_pluck.

## 1.4.0
* Add batch_pluck method to ActiveRecord storage adapter.

## 1.3.10
* Fix a bug preventing Prohibitions from accepting extra attributes.

## 1.3.9
* Fix a bug impacting duplicate new prohibited permissions in bulk persist.

## 1.3.8
* Improve the bulk_persistence method to include logical links, assignments.
* Remove repetitive warnings about missing columns that trigger in memory filtering.

## 1.3.7

* Add the ability to link policy elements in different policy machines.
* Add a migration for the `logical_links` table.

– Execute `bundle exec rails generate the_policy_machine:add_logical_links_table` and rerun `db:migrate` to use these changes.

_~ Many skipped updates to the Changelog. Sorry! ~_

## 0.0.2

* Fix: Operation sets now silently remove duplicates
* Transactional rollback available in active_record and in_memory
* Can now generate a list of all privileges a user has on an object with `#scoped_privileges`

## 0.0.1

* Initial open source release.
