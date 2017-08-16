require 'simplecov'
SimpleCov.start do
  add_group 'lib', 'lib'
  add_filter 'spec'
  add_filter 'test'
end

#require_relative '../test/test_helper.rb'

require 'rspec'
require 'pry'
require 'rake'
SPEC_DIR = File.expand_path("..", __FILE__)
lib_dir = File.expand_path("../lib", SPEC_DIR)

$LOAD_PATH.unshift(lib_dir)
$LOAD_PATH.uniq!

require 'policy_machine'

SmallNumber = 3.class #Integer in 2.4, Fixnum before that

Dir["./spec/support/**/*.rb"].each {|f| require f}

RSpec.configure do |config|
  config.mock_with :rspec
end
