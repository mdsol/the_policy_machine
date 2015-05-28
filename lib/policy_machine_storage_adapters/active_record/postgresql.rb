require 'active_record/hierarchical_query' # via gem activerecord-hierarchical_query

module PolicyMachineStorageAdapter
  class ActiveRecord

    class Assignment < ::ActiveRecord::Base
      attr_accessible :child_id, :parent_id
      # needs parent_id, child_id columns
      belongs_to :parent, class_name: :PolicyElement
      belongs_to :child, class_name: :PolicyElement

      def self.transitive_closure?(ancestor, descendant)
        descendants_of(ancestor).include?(descendant)
      end

      def self.descendants_of(element)
        recursive_query = join_recursive do |query|
          query.start_with(parent_id: element.id).connect_by(child_id: :parent_id)
        end
        PolicyElement.where(id: recursive_query.select('assignments.child_id'))
      end

      def self.ancestors_of(element)
        recursive_query = join_recursive do |query|
          query.start_with(child_id: element.id).connect_by(parent_id: :child_id)
        end
        PolicyElement.where(id: recursive_query.select('assignments.parent_id'))
      end

    end
  end
end
