# Contributing

If you find a bug:

* Check the "GitHub issue tracker" to see if anyone else has reported issue.
* If you don't see anything, create an issue with information on how to reproduce it.

If you want to contribute an enhancement or a fix:

* Fork the project on GitHub.
* Execute `bundle install`.
* Execute `rake pm:test:prepare` to configure your test environment.
* Write tests for your changes.
* Run all automated tests to see if your change broke anything or is providing anything less than 100% code coverage (see below).
* Commit the changes without making changes to any other files that aren't related to your enhancement or fix.
* Send a pull request.

## Running Automated Tests
Configure the test app with:

```
bundle exec rake pm:test:prepare
```

By default, the above command will configure the test database to be postgresql, but you can change this with:

```
bundle exec rake pm:test:prepare[mysql]
```

If this command fails with:
```
PG::ConnectionBad: could not connect to server: No such file or directory
```
Or a similar error, then try adding `localhost` to the test app's database.yml. Namely, navigate to `test/testapp/config/database.yml`, and in the `default` section add a `host` key with the value `localhost` and rerun the above command.

If nokogiri fails to install for the test app, then try installing it specifying your local system libraries like:
```
gem install nokogiri --use-system-libraries
```

Run all rspec tests with:

```
bundle exec rspec
```

Simplecov code coverage is generated automatically.  Any changes you make to this repository should
ensure that code coverage remains at at least 99.5%.  **No pull request will be merged that reduces
code coverage.**

## Making Your Own Policy Machine Storage Adapter

A template storage adapter is provided in `lib/policy_machine_storage_adapters/template.rb`. Copy this storage adapter as a starting point for making your own; implement all methods contained therein.

To test your storage adapter, adapt the tests in either `spec/policy_machine_storage_adapters/in_memory_spec.rb` or `spec/policy_machine_storage_adapters/neography_spec.rb`.

## Adding New Database Migrations

`the_policy_machine` manages its database migrations using Rails migrations and generators. Applications using `the_policy_machine` gem will update their code base with `the_policy_machine`'s latest database migrations by running:
```
bundle exec rails generate the_policy_machine:a_migration
```
In the above command, "the_policy_machine"  refers to the name of the directory `lib/generators/the_policy_machine`. It's just a namespace. "a_migration" refers to the name of a generator file in that directory.

To add a database migration for applications consuming `the_policy_machine` to use, add a new migration file in `lib/migrations/`, and add a new generator file in `lib/generators/`. Preferably namespace the generator by adding it under `lib/generators/the_policy_machine/`.

### Add New DB Migration Example

If you wanted to add a `parent_policy_machine_uuid` column to the `Assignment` table, then you would add the following files:
```ruby
# lib/migrations/add_parent_policy_machine_uuid_column.rb
class AddParentPolicyMachineUUIDColumn < ActiveRecord::Migration
  def change
    add_column :assignments, :parent_policy_machine_uuid, :string
  end
end
```

```ruby
# lib/generators/the_policy_machine/add_parent_policy_machine_uuid_column_generator.rb
module ThePolicyMachine
  module Generators
    class AddParentPolicyMachineUUIDColumnGenerator < Rails::Generators::Base
      source_root File.expand_path('../../../migrations', __FILE__)

      def generate_add_parent_policy_machine_uuid_column_generator_migration
        timestamp = Time.now.utc.strftime("%Y%m%d%H%M%S")
        copy_file('add_parent_policy_machine_uuid_column.rb', "db/migrate/#{timestamp}_add_parent_policy_machine_uuid_column.rb")
      end
    end
  end
end
```

Then, you would update the changelog for the next version of `the_policy_machine` to specify that applications should include this new migration in their codebase by running:
```
bundle exec rails generate the_policy_machine:add_parent_policy_machine_uuid_column
```
