require_relative './lib/policy_machine/version'

Gem::Specification.new do |s|
  s.name        = "policy_machine"
  s.version     = PolicyMachine::VERSION
  s.summary     = "Policy Machine!"
  s.description = "A ruby implementation of the Policy Machine authorization formalism."
  s.authors     = ['Matthew Szenher', 'Aaron Weiner']
  s.email       = s.authors.map{|name|name.sub(/(.).* (.*)/,'\1\2@mdsol.com')}
  s.homepage    = 'https://github.com/mdsol/the_policy_machine'
  s.license     = 'MIT'
  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.require_paths = ["lib"]

  s.add_dependency('activesupport', '~> 4.1')
  s.add_dependency('activerecord', '~> 4.1') #TODO optional dependency when not using active record adapter
  s.add_dependency('will_paginate')

  # Only required in ActiveRecord mode
  s.add_dependency('activerecord-import', '~> 0.12')
    # Only required for mysql
    s.add_dependency('mysql2')
    # Only required for postgres
    s.add_dependency('pg')
    s.add_dependency('activerecord-hierarchical_query', '~> 0.0')
    s.add_dependency('pluck_to_hash', '~> 1')

  s.add_development_dependency('rspec', '~> 3.5.0')
  s.add_development_dependency('simplecov', '~> 0.7.1')
  s.add_development_dependency('pry')
  s.add_development_dependency('pry-nav')
  s.add_development_dependency('byebug')
  s.add_development_dependency('neography', '~> 1.1')
  s.add_development_dependency('database_cleaner')
  s.add_development_dependency('rails', '~> 4.2')

end
