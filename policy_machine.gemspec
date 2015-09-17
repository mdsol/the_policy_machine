Gem::Specification.new do |s|
  s.name        = "policy_machine"
  s.version     = "0.0.2"
  s.summary     = "Policy Machine!"
  s.description = "A ruby implementation of the Policy Machine authorization formalism."
  s.authors     = ['Matthew Szenher', 'Aaron Weiner']
  s.email       = s.authors.map{|name|name.sub(/(.).* (.*)/,'\1\2@mdsol.com')}
  s.homepage    = 'https://github.com/mdsol/the_policy_machine'
  s.license     = 'MIT'
  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.require_paths = ["lib"]

  s.add_dependency('activesupport', '~> 3.2')

  s.add_development_dependency('rspec', '~> 2.13.0')
  s.add_development_dependency('simplecov', '~> 0.7.1')
  s.add_development_dependency('pry')
  s.add_development_dependency('neography', '~> 1.1')
  s.add_development_dependency('rails', '~> 3.2')
  s.add_development_dependency('mysql2')
  s.add_development_dependency('pg')
  s.add_development_dependency('database_cleaner')
  s.add_development_dependency('will_paginate', '~> 3.0.5')
  s.add_development_dependency('activerecord-hierarchical_query', '~> 0.0')

end
