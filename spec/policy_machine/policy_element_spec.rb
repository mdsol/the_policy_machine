require 'spec_helper'

describe PM::PolicyElement do
  let(:klass) do
    Class.new(PM::PolicyElement) do
      def initialize; end
    end
  end

  it 'raises if allowed_assignee_classes is not overridden in subclass' do
    expect { klass.new.send(:allowed_assignee_classes) }.to raise_error('Must override this method in a subclass')
  end

  it 'behaves normally when an unknown method is called' do
    expect { klass.new.creat }.to raise_error(NoMethodError, /^undefined method `creat' for #<#<Class:/)
  end
end
