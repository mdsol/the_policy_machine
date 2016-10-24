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

      def self.descendants_of(element_or_scope)
        #FIXME: Preloading with to_a seems to be necessary because putting complex sql in start_with can
        # lead to degenerate performance (noticed in ancestors_of call in accessible_objects)
        # Ideally, fix the SQL so it's both a single call and performant
        element_or_scope = [*element_or_scope]
        transaction_without_mergejoin do
          case element_or_scope.size
          when 0
            PolicyElement.none
          when 1
            PolicyElement.where('"policy_elements"."id" IN (SELECT assignments__recursive.child_id FROM (WITH RECURSIVE "assignments__recursive" AS ( SELECT "assignments"."id", "assignments"."child_id", "assignments"."parent_id" FROM "assignments" WHERE "assignments"."parent_id" = ? UNION ALL SELECT "assignments"."id", "assignments"."child_id", "assignments"."parent_id" FROM "assignments" INNER JOIN "assignments__recursive" ON "assignments__recursive"."child_id" = "assignments"."parent_id" ) SELECT "assignments__recursive".* FROM "assignments__recursive") AS "assignments__recursive")', element_or_scope.first.id)
          else
            PolicyElement.where('"policy_elements"."id" IN (SELECT assignments__recursive.child_id FROM (WITH RECURSIVE "assignments__recursive" AS ( SELECT "assignments"."id", "assignments"."child_id", "assignments"."parent_id" FROM "assignments" WHERE "assignments"."parent_id" in (?) UNION ALL SELECT "assignments"."id", "assignments"."child_id", "assignments"."parent_id" FROM "assignments" INNER JOIN "assignments__recursive" ON "assignments__recursive"."child_id" = "assignments"."parent_id" ) SELECT "assignments__recursive".* FROM "assignments__recursive") AS "assignments__recursive")', element_or_scope.map(&:id))
          end
        end
      end

      def self.ancestors_of(element_or_scope)
        #FIXME: Also, removing the superfluous join of Assignment onto the recursive call is hugely beneficial to performance, but not supported
        # by hierarchical_query. Since this is a major performance pain point, generating raw SQL for now.
        element_or_scope = [*element_or_scope]
        transaction_without_mergejoin do
          case element_or_scope.size
          when 0
            PolicyElement.none
          when 1
            PolicyElement.where('"policy_elements"."id" IN (SELECT assignments__recursive.parent_id FROM (WITH RECURSIVE "assignments__recursive" AS ( SELECT "assignments"."id", "assignments"."parent_id", "assignments"."child_id" FROM "assignments" WHERE "assignments"."child_id" = ? UNION ALL SELECT "assignments"."id", "assignments"."parent_id", "assignments"."child_id" FROM "assignments" INNER JOIN "assignments__recursive" ON "assignments__recursive"."parent_id" = "assignments"."child_id" ) SELECT "assignments__recursive".* FROM "assignments__recursive") AS "assignments__recursive")', element_or_scope.first.id)
          else
            PolicyElement.where('"policy_elements"."id" IN (SELECT assignments__recursive.parent_id FROM (WITH RECURSIVE "assignments__recursive" AS ( SELECT "assignments"."id", "assignments"."parent_id", "assignments"."child_id" FROM "assignments" WHERE "assignments"."child_id" in (?) UNION ALL SELECT "assignments"."id", "assignments"."parent_id", "assignments"."child_id" FROM "assignments" INNER JOIN "assignments__recursive" ON "assignments__recursive"."parent_id" = "assignments"."child_id" ) SELECT "assignments__recursive".* FROM "assignments__recursive") AS "assignments__recursive")', element_or_scope.map(&:id))
          end
        end
      end

      def self.transaction_without_mergejoin(&block)
        Assignment.transaction do
          Assignment.connection.execute("set local enable_mergejoin = false")
          yield
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
