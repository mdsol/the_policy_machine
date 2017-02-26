# Changelog

## 1.3.7

* Add the ability to assign policy elements in different policy machines.
* Add a migration for the `cross_assignments` table.

– Execute `bundle exec rails generate the_policy_machine:add_cross_assignments_table` and rerun `db:migrate` to use these changes.

_~ Many skipped updates to the Changelog. Sorry! ~_

## 0.0.2

* Fix: Operation sets now silently remove duplicates
* Transactional rollback available in active_record and in_memory
* Can now generate a list of all privileges a user has on an object with `#scoped_privileges`

## 0.0.1

* Initial open source release.
