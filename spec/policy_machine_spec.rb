require 'spec_helper'

describe PolicyMachine do
  it_behaves_like 'a policy machine' do
    let(:policy_machine) { PolicyMachine.new(:name => 'default PM') }
  end

  describe '.configure' do
    it 'accepts policy element default scope configuration' do
      PolicyMachine.configure do |config|
        config.policy_element_default_scope = :foo
      end

      expect(PolicyMachine.configuration.policy_element_default_scope).to eq(:foo)
    end
  end
end
