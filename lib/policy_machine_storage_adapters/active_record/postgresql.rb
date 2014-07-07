# Simple postgresql transitive closure implementation
# TODO: Look into taking better advantage of Postgres for this

module PolicyMachineStorageAdapter
  class ActiveRecord
    class Assignment

      def add_to_transitive_closure
        connection.execute("Insert into transitive_closure values (#{parent_id}, #{child_id})")
        connection.execute("Insert into transitive_closure
             select distinct parents_ancestors.ancestor_id, childs_descendants.descendant_id from
              transitive_closure parents_ancestors,
              transitive_closure childs_descendants
             where
              (parents_ancestors.descendant_id = #{parent_id} or parents_ancestors.ancestor_id = #{parent_id})
              and (childs_descendants.ancestor_id = #{child_id} or childs_descendants.descendant_id = #{child_id})
              and not exists (Select * from transitive_closure preexisting where preexisting.ancestor_id = parents_ancestors.ancestor_id
                                                                           and preexisting.descendant_id = childs_descendants.descendant_id)")
      end

      def remove_from_transitive_closure
        parents_ancestors = connection.execute("Select ancestor_id from transitive_closure where descendant_id=#{parent_id}")
        childs_descendants = connection.execute("Select descendant_id from transitive_closure where ancestor_id=#{child_id}")
        parents_ancestors = parents_ancestors.values.<<(parent_id).join(',')
        childs_descendants = childs_descendants.values.<<(child_id).join(',')

        connection.execute("Delete from transitive_closure where
          ancestor_id in (#{parents_ancestors}) and
          descendant_id in (#{childs_descendants}) and
          not exists (Select * from assignments where parent_id=ancestor_id and child_id=descendant_id)
        ")

        connection.execute("Insert into transitive_closure
            select distinct ancestors_surviving_relationships.ancestor_id, descendants_surviving_relationships.descendant_id
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
  end
end
