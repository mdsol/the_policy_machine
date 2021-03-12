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

  s.add_dependency('activesupport')
  s.add_dependency('activerecord') #TODO optional dependency when not using active record adapter
  s.add_dependency('will_paginate')
  s.add_dependency('bootsnap')
  s.add_dependency('listen')

  # Only required in ActiveRecord mode
  s.add_dependency('activerecord-import', '~> 1.0')

  # projects using this gem should add the gem for whichever adapter they use
  s.add_development_dependency('mysql2')
  s.add_development_dependency('pg')

  s.add_development_dependency('rspec')
  s.add_development_dependency('simplecov', '~> 0.7.1')
  s.add_development_dependency('pry')
  s.add_development_dependency('pry-nav')
  s.add_development_dependency('byebug')
  s.add_development_dependency('neography', '~> 1.1')
  s.add_development_dependency('database_cleaner')
  s.add_development_dependency('rails', '~> 6.0')
end
