require_relative 'lib/policy_machine/version'

Gem::Specification.new do |s|
  s.name        = 'policy_machine'
  s.version     = PolicyMachine::VERSION
  s.summary     = 'Policy Machine!'
  s.description = 'A ruby implementation of the Policy Machine authorization formalism.'
  s.authors     = ['Matthew Szenher', 'Aaron Weiner']
  s.email       = s.authors.map { |name| name.sub(/(.).* (.*)/, "\1\2@mdsol.com") }
  s.license     = 'MIT'
  s.required_ruby_version = Gem::Requirement.new('>= 2.6.0')

  s.homepage = 'https://github.com/mdsol/the_policy_machine'
  s.metadata['homepage_uri'] = s.homepage
  s.metadata['source_code_uri'] = s.homepage
  s.metadata['changelog_uri'] = "#{s.homepage}/blob/develop/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  s.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  s.require_paths = ['lib']

  s.add_dependency 'activerecord' # TODO: optional dependency when not using active record adapter
  s.add_dependency 'activesupport'
  s.add_dependency 'bootsnap'
  s.add_dependency 'listen'
  s.add_dependency 'will_paginate'

  # Only required in ActiveRecord mode
  s.add_dependency 'activerecord-import', '~> 1.0'

  # projects using this gem should add the gem for whichever adapter they use
  s.add_development_dependency 'mysql2'
  s.add_development_dependency 'pg'

  s.add_development_dependency 'byebug'
  s.add_development_dependency 'database_cleaner'
  s.add_development_dependency 'neography', '~> 1.1'
  s.add_development_dependency 'pry'
  s.add_development_dependency 'pry-nav'
  s.add_development_dependency 'rails', '~> 6.1'
  s.add_development_dependency 'rspec'
  s.add_development_dependency 'rubocop', '= 1.23.0'
  s.add_development_dependency 'rubocop-mdsol', '~> 0.1'
  s.add_development_dependency 'rubocop-performance', '= 1.12.0'
  s.add_development_dependency 'simplecov', '~> 0.7'
end
