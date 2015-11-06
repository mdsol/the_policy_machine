require 'active_record/hierarchical_query' # via gem activerecord-hierarchical_query

module PolicyMachineStorageAdapter
  class ActiveRecord

    class Assignment < ::ActiveRecord::Base
      # needs parent_id, child_id columns
      belongs_to :parent, class_name: 'PolicyElement', foreign_key: :parent_id
      belongs_to :child, class_name: 'PolicyElement', foreign_key: :child_id

      def self.transitive_closure?(ancestor, descendant)
        descendants_of(ancestor).include?(descendant)
      end

      def self.descendants_of(element)
        recursive_query = join_recursive do |query|
          query.start_with(parent_id: element.id).connect_by(child_id: :parent_id).nocycle
        end
        PolicyElement.where(id: recursive_query.select('assignments.child_id'))
      end

      def self.ancestors_of(element)
        recursive_query = join_recursive do |query|
          query.start_with(child_id: element.id).connect_by(parent_id: :child_id).nocycle
        end
        PolicyElement.where(id: recursive_query.select('assignments.parent_id'))
      end

    end

    class Adapter

      # Support substring searching and Postgres Array membership
      def self.apply_include_condition(scope: , key: , value: , klass: )
        array_type = klass.columns_hash[key.to_s].sql_type.include?('[]')
        if array_type
          scope.where("? = ANY(#{key})", value)
        else
          scope.where("#{key} LIKE '%?%'", value.to_s.gsub(/([%_])/, '\\\\\0'))
        end
      end

    end

  end
end
