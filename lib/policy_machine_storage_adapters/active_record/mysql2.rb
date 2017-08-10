module PolicyMachineStorageAdapter
  class ActiveRecord
    class Assignment < ::ActiveRecord::Base

      class TransitiveClosure < ::ActiveRecord::Base
        self.table_name = 'transitive_closure'
        # needs ancestor_id, descendant_id columns
        belongs_to :ancestor, class_name: :PolicyElement
        belongs_to :descendant, class_name: :PolicyElement
      end

      after_create :add_to_transitive_closure
      after_destroy :remove_from_transitive_closure
      attr_accessible :child_id, :parent_id
      # needs parent_id, child_id columns
      belongs_to :parent, class_name: :PolicyElement
      belongs_to :child, class_name: :PolicyElement

      def self.transitive_closure?(ancestor, descendant)
        TransitiveClosure.exists?(ancestor_id: ancestor.id, descendant_id: descendant.id)
      end

      def self.descendants_of(element_id)
        PolicyElement.joins('inner join transitive_closure on policy_elements.id=transitive_closure.descendant_id').where(
          "transitive_closure.ancestor_id = #{element_id}"
        )
      end

      def self.ancestors_of(element_id)
        PolicyElement.joins('inner join transitive_closure on policy_elements.id=transitive_closure.ancestor_id').where(
          "transitive_closure.descendant_id = #{element_id}"
        )
      end

      def add_to_transitive_closure
        connection.execute("Insert ignore into transitive_closure values (#{parent_id}, #{child_id})")
        connection.execute("Insert ignore into transitive_closure
             select parents_ancestors.ancestor_id, childs_descendants.descendant_id from
              transitive_closure parents_ancestors,
              transitive_closure childs_descendants
             where
              (parents_ancestors.descendant_id = #{parent_id} or parents_ancestors.ancestor_id = #{parent_id})
              and (childs_descendants.ancestor_id = #{child_id} or childs_descendants.descendant_id = #{child_id})")
      end

      def remove_from_transitive_closure
        parents_ancestors = connection.execute("Select ancestor_id from transitive_closure where descendant_id=#{parent_id}")
        childs_descendants = connection.execute("Select descendant_id from transitive_closure where ancestor_id=#{child_id}")
        parents_ancestors = parents_ancestors.to_a.<<(parent_id).join(',')
        childs_descendants = childs_descendants.to_a.<<(child_id).join(',')

        connection.execute("Delete from transitive_closure where
          ancestor_id in (#{parents_ancestors}) and
          descendant_id in (#{childs_descendants}) and
          not exists (Select * from assignments where parent_id=ancestor_id and child_id=descendant_id)
        ")

        connection.execute("Insert ignore into transitive_closure
            select ancestors_surviving_relationships.ancestor_id, descendants_surviving_relationships.descendant_id
            from
              transitive_closure ancestors_surviving_relationships,
              transitive_closure descendants_surviving_relationships
            where
              (ancestors_surviving_relationships.ancestor_id in (#{parents_ancestors}))
              and (descendants_surviving_relationships.descendant_id in (#{childs_descendants}))
              and (ancestors_surviving_relationships.descendant_id = descendants_surviving_relationships.ancestor_id)
        ")
      end
    end

    class Adapter

      # Support substring searching
      def self.apply_include_condition(scope: , key: , value: , klass: )
        scope.where("#{key} LIKE '%#{value.to_s.gsub(/([%_])/, '\\\\\0')}%'", )
      end

    end

  end
end
