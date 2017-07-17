# Changelog

## 1.6.0
* Add pluck_parents and pluck_children methods to ActiveRecord storage adapter.

## 1.5.4
* Give precedence to column attribute accessors instead of extra_attributes during store_attributes memoization.

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
