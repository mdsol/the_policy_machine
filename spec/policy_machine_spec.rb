require 'spec_helper'

describe PolicyMachine do
  it_behaves_like 'a policy machine' do
    let(:policy_machine) { PolicyMachine.new(name: 'default PM') }
  end
end
