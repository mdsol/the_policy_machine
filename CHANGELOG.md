# Changelog

## 1.4.2
* Fix the ActiveRecord Adapter to retry on `find_or_create` uniqueness violations.

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
