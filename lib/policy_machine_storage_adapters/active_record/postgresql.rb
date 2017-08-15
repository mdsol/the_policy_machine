require 'active_record/hierarchical_query' # via gem activerecord-hierarchical_query

module PolicyMachineStorageAdapter
  class ActiveRecord

    class Assignment < ::ActiveRecord::Base
      # needs parent_id, child_id columns
      belongs_to :parent, class_name: 'PolicyElement', foreign_key: :parent_id
      belongs_to :child, class_name: 'PolicyElement', foreign_key: :child_id

      def self.transitive_closure?(ancestor, descendant)
        descendants_of(ancestor.id).include?(descendant)
      end

      def self.descendants_of(ids)
        #FIXME: Preloading with to_a seems to be necessary because putting complex sql in start_with can
        # lead to degenerate performance (noticed in ancestors_of call in accessible_objects)
        # Ideally, fix the SQL so it's both a single call and performant
        ids = [*ids]
        case ids.size
        when 0
          PolicyElement.none
        when 1
          PolicyElement.where('"policy_elements"."id" IN (SELECT assignments__recursive.child_id FROM (WITH RECURSIVE "assignments__recursive" AS ( SELECT "assignments"."id", "assignments"."child_id", "assignments"."parent_id" FROM "assignments" WHERE "assignments"."parent_id" = ? UNION SELECT "assignments"."id", "assignments"."child_id", "assignments"."parent_id" FROM "assignments" INNER JOIN "assignments__recursive" ON "assignments__recursive"."child_id" = "assignments"."parent_id" ) SELECT "assignments__recursive".* FROM "assignments__recursive") AS "assignments__recursive")', ids.first)
        else
          PolicyElement.where('"policy_elements"."id" IN (SELECT assignments__recursive.child_id FROM (WITH RECURSIVE "assignments__recursive" AS ( SELECT "assignments"."id", "assignments"."child_id", "assignments"."parent_id" FROM "assignments" WHERE "assignments"."parent_id" in (?) UNION SELECT "assignments"."id", "assignments"."child_id", "assignments"."parent_id" FROM "assignments" INNER JOIN "assignments__recursive" ON "assignments__recursive"."child_id" = "assignments"."parent_id" ) SELECT "assignments__recursive".* FROM "assignments__recursive") AS "assignments__recursive")', ids)
        end
      end

      def self.ancestors_of(ids)
        #FIXME: Also, removing the superfluous join of Assignment onto the recursive call is hugely beneficial to performance, but not supported
        # by hierarchical_query. Since this is a major performance pain point, generating raw SQL for now.
        ids = [*ids]
        case ids.size
        when 0
          PolicyElement.none
        when 1
          PolicyElement.where('"policy_elements"."id" IN (SELECT assignments__recursive.parent_id FROM (WITH RECURSIVE "assignments__recursive" AS ( SELECT "assignments"."id", "assignments"."parent_id", "assignments"."child_id" FROM "assignments" WHERE "assignments"."child_id" = ? UNION SELECT "assignments"."id", "assignments"."parent_id", "assignments"."child_id" FROM "assignments" INNER JOIN "assignments__recursive" ON "assignments__recursive"."parent_id" = "assignments"."child_id" ) SELECT "assignments__recursive".* FROM "assignments__recursive") AS "assignments__recursive")', ids.first)
        else
          PolicyElement.where('"policy_elements"."id" IN (SELECT assignments__recursive.parent_id FROM (WITH RECURSIVE "assignments__recursive" AS ( SELECT "assignments"."id", "assignments"."parent_id", "assignments"."child_id" FROM "assignments" WHERE "assignments"."child_id" in (?) UNION SELECT "assignments"."id", "assignments"."parent_id", "assignments"."child_id" FROM "assignments" INNER JOIN "assignments__recursive" ON "assignments__recursive"."parent_id" = "assignments"."child_id" ) SELECT "assignments__recursive".* FROM "assignments__recursive") AS "assignments__recursive")', ids)
        end
      end

      # Returns the operation set IDs from the given list where the operation is
      # a descendant of the operation set.
      def self.filter_operation_set_list_by_assigned_operation(operation_set_ids, operation_id)
        query =
          "WITH RECURSIVE assignments_recursive AS (
            (
              SELECT parent_id, child_id, ARRAY[parent_id] AS parents
              FROM assignments
              WHERE parent_id IN (#{operation_set_ids.join(',')})
            )
            UNION
            (
              SELECT assignments.parent_id, assignments.child_id, assignments.parent_id || parents
              FROM assignments
              INNER JOIN assignments_recursive
              ON assignments_recursive.child_id = assignments.parent_id
            )
          )

          SELECT parents[1]
          FROM assignments_recursive
          JOIN policy_elements
          ON policy_elements.id = assignments_recursive.child_id
          WHERE policy_elements.unique_identifier = '#{operation_id}'
          AND type = 'PolicyMachineStorageAdapter::ActiveRecord::Operation'"
        PolicyElement.connection.exec_query(query).rows.flatten.map(&:to_i)
      end
    end

    class LogicalLink < ::ActiveRecord::Base

      belongs_to :link_parent, class_name: 'PolicyElement', foreign_key: :link_parent_id
      belongs_to :link_child, class_name: 'PolicyElement', foreign_key: :link_child_id

      def self.transitive_closure?(ancestor, descendant)
        descendants_of(ancestor).include?(descendant)
      end

      def self.descendants_of(element_or_scope)
        #FIXME: Preloading with to_a seems to be necessary because putting complex sql in start_with can
        # lead to degenerate performance (noticed in ancestors_of call in accessible_objects)
        # Ideally, fix the SQL so it's both a single call and performant
        element_or_scope = [*element_or_scope]
        case element_or_scope.size
        when 0
          PolicyElement.none
        when 1
          PolicyElement.where('"policy_elements"."id" IN (SELECT logical_links__recursive.link_child_id FROM (WITH RECURSIVE "logical_links__recursive" AS ( SELECT "logical_links"."id", "logical_links"."link_child_id", "logical_links"."link_parent_id" FROM "logical_links" WHERE "logical_links"."link_parent_id" = ? UNION SELECT "logical_links"."id", "logical_links"."link_child_id", "logical_links"."link_parent_id" FROM "logical_links" INNER JOIN "logical_links__recursive" ON "logical_links__recursive"."link_child_id" = "logical_links"."link_parent_id" ) SELECT "logical_links__recursive".* FROM "logical_links__recursive") AS "logical_links__recursive")', element_or_scope.first.id)
        else
          PolicyElement.where('"policy_elements"."id" IN (SELECT logical_links__recursive.link_child_id FROM (WITH RECURSIVE "logical_links__recursive" AS ( SELECT "logical_links"."id", "logical_links"."link_child_id", "logical_links"."link_parent_id" FROM "logical_links" WHERE "logical_links"."link_parent_id" in (?) UNION SELECT "logical_links"."id", "logical_links"."link_child_id", "logical_links"."link_parent_id" FROM "logical_links" INNER JOIN "logical_links__recursive" ON "logical_links__recursive"."link_child_id" = "logical_links"."link_parent_id" ) SELECT "logical_links__recursive".* FROM "logical_links__recursive") AS "logical_links__recursive")', element_or_scope.map(&:id))
        end
      end

      def self.ancestors_of(element_or_scope)
        #FIXME: Also, removing the superfluous join of Assignment onto the recursive call is hugely beneficial to performance, but not supported
        # by hierarchical_query. Since this is a major performance pain point, generating raw SQL for now.
        element_or_scope = [*element_or_scope]
        case element_or_scope.size
        when 0
          PolicyElement.none
        when 1
          PolicyElement.where('"policy_elements"."id" IN (SELECT logical_links__recursive.link_parent_id FROM (WITH RECURSIVE "logical_links__recursive" AS ( SELECT "logical_links"."id", "logical_links"."link_parent_id", "logical_links"."link_child_id" FROM "logical_links" WHERE "logical_links"."link_child_id" = ? UNION SELECT "logical_links"."id", "logical_links"."link_parent_id", "logical_links"."link_child_id" FROM "logical_links" INNER JOIN "logical_links__recursive" ON "logical_links__recursive"."link_parent_id" = "logical_links"."link_child_id" ) SELECT "logical_links__recursive".* FROM "logical_links__recursive") AS "logical_links__recursive")', element_or_scope.first.id)
        else
          PolicyElement.where('"policy_elements"."id" IN (SELECT logical_links__recursive.link_parent_id FROM (WITH RECURSIVE "logical_links__recursive" AS ( SELECT "logical_links"."id", "logical_links"."link_parent_id", "logical_links"."link_child_id" FROM "logical_links" WHERE "logical_links"."link_child_id" in (?) UNION SELECT "logical_links"."id", "logical_links"."link_parent_id", "logical_links"."link_child_id" FROM "logical_links" INNER JOIN "logical_links__recursive" ON "logical_links__recursive"."link_parent_id" = "logical_links"."link_child_id" ) SELECT "logical_links__recursive".* FROM "logical_links__recursive") AS "logical_links__recursive")', element_or_scope.map(&:id))
        end
      end
    end

    class Adapter

      # Support substring searching and Postgres Array membership
      def self.apply_include_condition(scope: , key: , value: , klass: )
        if klass.columns_hash[key.to_s].array
          [*value].reduce(scope) { |rel, val| rel.where("? = ANY(#{key})", val) }
        else
          scope.where("#{key} LIKE '%#{value.to_s.gsub(/([%_])/, '\\\\\0')}%'", )
        end
      end
    end
  end
end
