# This is a necessary patch to allow AR::Store to methodize singleton methods on instances
module ActiveRecord
  module Store
    module ClassMethods
      def store_accessor(store_attribute, options={}, *keys)
        Array(keys).flatten.each do |key|
          debugger
          method_type = options[:instance] ? 'singleton_method' : 'method'
          send("define_singleton_method", "#{key}=") do |value|
            send("#{store_attribute}=", {}) unless send(store_attribute).is_a?(Hash)
            send("#{store_attribute}_will_change!")
            send(store_attribute)[key] = value
          end
    
          send("define_singleton_method", key) do
            send("#{store_attribute}=", {}) unless send(store_attribute).is_a?(Hash)
            send(store_attribute)[key]            
          end
        end
      end
    end
  end
end
