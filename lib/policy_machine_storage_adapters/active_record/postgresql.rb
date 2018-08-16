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
        query = <<-SQL
          id IN (
            WITH RECURSIVE assignments_recursive AS (
              (
                SELECT child_id, parent_id
                FROM assignments
                WHERE parent_id in (?)
              )
              UNION ALL
              (
                SELECT assignments.child_id, assignments.parent_id
                FROM assignments
                INNER JOIN assignments_recursive
                ON assignments_recursive.child_id = assignments.parent_id
                #{::PolicyMachineStorageAdapter::ActiveRecord::SQLHelpers.recursive_default_scope_modifier('assignments_recursive', 'child_id')}
              )
            )

            SELECT assignments_recursive.child_id
            FROM assignments_recursive
          )
        SQL

        PolicyElement.where(query, [*element_or_scope].map(&:id))
      end

      def self.ancestors_of(element_or_scope)
        query = <<-SQL
          id IN (
            WITH RECURSIVE assignments_recursive AS (
              (
                SELECT parent_id, child_id
                FROM assignments
                WHERE child_id IN (?)
              )
              UNION ALL
              (
                SELECT assignments.parent_id, assignments.child_id
                FROM assignments
                INNER JOIN assignments_recursive
                ON assignments_recursive.parent_id = assignments.child_id
                #{::PolicyMachineStorageAdapter::ActiveRecord::SQLHelpers.recursive_default_scope_modifier('assignments_recursive', 'parent_id')}
              )
            )

            SELECT assignments_recursive.parent_id
            FROM assignments_recursive
          )
        SQL

        PolicyElement.where(query, [*element_or_scope].map(&:id))
      end

      # Return an ActiveRecord::Relation containing the ids of all ancestors and the
      # interstitial relationships, as a string of ancestor_ids
      def self.find_ancestor_ids(root_element_ids)
        query = <<-SQL
          WITH RECURSIVE assignments_recursive AS (
            (
              SELECT parent_id, child_id
              FROM assignments
              WHERE #{sanitize_sql_for_conditions(["child_id IN (:root_ids)", root_ids: root_element_ids])}
            )
            UNION ALL
            (
              SELECT assignments.parent_id, assignments.child_id
              FROM assignments
              INNER JOIN assignments_recursive
              ON assignments_recursive.parent_id = assignments.child_id
              #{::PolicyMachineStorageAdapter::ActiveRecord::SQLHelpers.recursive_default_scope_modifier('assignments_recursive', 'parent_id')}
            )
          )

          SELECT child_id as id, array_agg(parent_id) as ancestor_ids
          FROM assignments_recursive
          GROUP BY child_id
        SQL

        PolicyElement.connection.exec_query(query)
      end

      # Returns the operation set IDs from the given list where the operation is
      # a descendant of the operation set.
      # TODO: Generalize this so that we can arbitrarily filter recursive assignments calls.
      def self.filter_operation_set_list_by_assigned_operation(operation_set_ids, operation_id)
        query = <<-SQL
          WITH RECURSIVE assignments_recursive AS (
            (
              SELECT parent_id, child_id, ARRAY[parent_id] AS parents
              FROM assignments
              WHERE #{sanitize_sql_for_conditions(["parent_id IN (:opset_ids)", opset_ids: operation_set_ids])}
            )
            UNION ALL
            (
              SELECT assignments.parent_id, assignments.child_id, (parents || assignments.parent_id)
              FROM assignments
              INNER JOIN assignments_recursive
              ON assignments_recursive.child_id = assignments.parent_id
              #{::PolicyMachineStorageAdapter::ActiveRecord::SQLHelpers.recursive_default_scope_modifier('assignments_recursive', 'child_id')}
            )
          )

          SELECT parents[1]
          FROM assignments_recursive
          JOIN policy_elements
          ON policy_elements.id = assignments_recursive.child_id
          #{::PolicyMachineStorageAdapter::ActiveRecord::SQLHelpers.default_scope_modifier}
          WHERE #{sanitize_sql_for_conditions(["policy_elements.unique_identifier=:op_id", op_id: operation_id])}
          AND type = 'PolicyMachineStorageAdapter::ActiveRecord::Operation'
          #{::PolicyMachineStorageAdapter::ActiveRecord::SQLHelpers.default_scope_modifier}
        SQL

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
        query = <<-SQL
          id IN (
            WITH RECURSIVE logical_links_recursive AS (
              (
                SELECT link_child_id, link_parent_id
                FROM logical_links
                WHERE link_parent_id in (?)
              )
              UNION ALL
              (
                SELECT logical_links.link_child_id, logical_links.link_parent_id
                FROM logical_links
                INNER JOIN logical_links_recursive
                ON logical_links_recursive.link_child_id = logical_links.link_parent_id
                #{::PolicyMachineStorageAdapter::ActiveRecord::SQLHelpers.recursive_default_scope_modifier('logical_links_recursive', 'link_child_id')}
              )
            )

            SELECT logical_links_recursive.link_child_id
            FROM logical_links_recursive
          )
        SQL

        PolicyElement.where(query, [*element_or_scope].map(&:id))
      end

      def self.ancestors_of(element_or_scope)
        query = <<-SQL
          id IN (
            WITH RECURSIVE logical_links_recursive AS (
              (
                SELECT link_parent_id, link_child_id
                FROM logical_links
                WHERE link_child_id IN (?)
              )
              UNION ALL
              (
                SELECT logical_links.link_parent_id, logical_links.link_child_id
                FROM logical_links
                INNER JOIN logical_links_recursive
                ON logical_links_recursive.link_parent_id = logical_links.link_child_id
                #{::PolicyMachineStorageAdapter::ActiveRecord::SQLHelpers.recursive_default_scope_modifier('logical_links_recursive', 'link_parent_id')}
              )
            )

            SELECT logical_links_recursive.link_parent_id
            FROM logical_links_recursive
          )
        SQL

        PolicyElement.where(query, [*element_or_scope].map(&:id))
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

    module SQLHelpers

      # Dynamically generates PolicyElement's default scope (if one is set) as an
      # AND clause
      # e.g. "AND 'policy_elements'.'color' IS NULL"
      def self.default_scope_modifier
        if PolicyMachine.configuration.policy_element_default_scope
          "AND #{PolicyElement.where(nil).to_sql.split("WHERE ")[1]}"
        else
          ''
        end
      end

      # Dynamically generates PolicyElement's default scope (if one is set) for
      # injection into recursive queries. Pass in the recursive table name and
      # the id column that is being built.
      # e.g.
      # recursive_default_scope_modifier('assignments_recursive', 'child_id')
      # => """
      # WHERE assignments_recursive.child_id in (
      # SELECT id
      # FROM policy_elements
      # WHERE 1=1
      # AND 'policy_elements'.'color' IS NULL
      # )
      # """
      def self.recursive_default_scope_modifier(table, id_column)
        if PolicyMachine.configuration.policy_element_default_scope
          # Dynamically generate PolicyElement's default scope as a clause for recursive queries
          """
          WHERE #{table}.#{id_column} in (
            SELECT id
            FROM policy_elements
            WHERE 1=1
              #{default_scope_modifier}
          )
          """
        else
          ''
        end
      end
    end
  end
end
