Gem::Specification.new do |s|
  s.name        = "policy_machine"
  s.version     = "0.0.1"
  s.summary     = "Policy Machine!"
  s.description = "A ruby implementation of the Policy Machine authorization formalism."
  s.authors     = ['Matthew Szenher', 'Aaron Weiner']
  s.email       = ""
  s.homepage    = 'https://github.com/mdsol/the_policy_machine'
  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.require_paths = ["lib"]

  s.add_dependency('activesupport')

  s.add_development_dependency('rspec', '~> 2.13.0')
  s.add_development_dependency('simplecov', '~> 0.7.1')
  s.add_development_dependency('debugger', '~> 1.6.0')
  s.add_development_dependency('neography', '~> 1.1')
  s.add_development_dependency('rails')
  s.add_development_dependency('mysql2')
  s.add_development_dependency('database_cleaner')

end
