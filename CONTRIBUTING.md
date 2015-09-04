# Contributing

If you find a bug:

* Check the "GitHub issue tracker" to see if anyone else has reported issue.
* If you don't see anything, create an issue with information on how to reproduce it.

If you want to contribute an enhancement or a fix:

* Fork the project on GitHub.
* bundle install
* Make your changes with tests.
* Run all automated tests to see if your change broke anything or is providing anything less than 100% code coverage (see below).
* Commit the changes without making changes to any other files that aren't related to your enhancement or fix.
* Send a pull request.

## Running Automated Tests

First cd into the test/dummy directory and create the test db with:

```
[bundle exec] rake db:create
[bundle exec] rake db:migrate
[bundle exec] rake db:test:prepare
```

Run all rspec with:

```
[bundle exec] rspec
```

Simplecov code coverage is generated automatically.  Any changes you make to this repository should
ensure that code coverage remains at at least 99.5%.  **No pull request will be merged that reduces
code coverage.**

## Making Your Own Policy Machine Storage Adapter

A template storage adapter is provided in `lib/policy_machine_storage_adapters/template.rb`.  Copy this 
storage adapter as a starting point for making your own; implement all methods contained therein.

To test your storage adapter, adapt the tests in either `spec/policy_machine_storage_adapters/in_memory_spec.rb` or
`spec/policy_machine_storage_adapters/neography_spec.rb`.
