require 'active_record/hierarchical_query' # via gem activerecord-hierarchical_query

module PolicyMachineStorageAdapter
  class ActiveRecord
    class Privilege
      def self.derive_privilege(user_or_attribute, operation, object_or_attribute, ignore_prohibitions: false)
        user_or_attribute_id = user_or_attribute.id
        operation_id = operation.try(:unique_identifier) || operation.to_s
        prohibition_id = ::PM::Prohibition.on(operation.to_s)
        object_or_attribute_id = object_or_attribute.id

        query = <<-SQL
WITH RECURSIVE operators AS (
SELECT
    #{user_or_attribute_id} AS child_id,
    0 AS parent_id

UNION ALL

SELECT a.child_id, a.parent_id
FROM assignments a
JOIN operators o
    ON o.child_id = a.parent_id
),

operables AS (
SELECT
    #{object_or_attribute_id} AS child_id,
    0 AS parent_id

UNION ALL

SELECT a.child_id, a.parent_id
FROM assignments a
JOIN operables o
    ON o.child_id = a.parent_id
),

accessible_operations AS (
SELECT
    a.parent_id AS operation_set_id,
    a.child_id
FROM assignments a
JOIN (
    SELECT DISTINCT operation_set_id
    FROM operators
    FULL OUTER JOIN policy_element_associations peas
        ON peas.user_attribute_id = operators.child_id
    FULL OUTER JOIN operables
        ON peas.object_attribute_id = operables.child_id
    WHERE 1=1
        AND peas.user_attribute_id IN (operators.child_id)
        AND peas.object_attribute_id IN (operables.child_id)
) base_associations
    ON a.parent_id = base_associations.operation_set_id

UNION

SELECT
    ao.operation_set_id,
    a.child_id
FROM assignments a
JOIN accessible_operations ao
    ON ao.child_id = a.parent_id
)

SELECT
    pe.unique_identifier
FROM (
    SELECT DISTINCT child_id FROM accessible_operations
) ao
JOIN policy_elements pe
    ON pe.id = ao.child_id
    AND pe.unique_identifier IN ('#{operation_id}', '#{prohibition_id}')
WHERE 1=1
    AND pe.id = ao.child_id
    AND pe.unique_identifier IN ('#{operation_id}', '#{prohibition_id}')
SQL

        # Execute the query and get the value of the count
        result = ::ActiveRecord::Base.connection.execute(query)
        rows = result.map { |row| row["unique_identifier"] }

        if ignore_prohibitions
          rows.include?(operation_id)
        else
          rows == [operation_id]
        end
      end
    end

    class PolicyElementAssociation
      def self.with_accessible_operation(associations, operation)
        query = <<-SQL
          operation_set_id IN (
            WITH RECURSIVE accessible_operations AS (
              (
                SELECT
                  child_id,
                  parent_id,
                  parent_id AS operation_set_id
                FROM assignments
                WHERE parent_id IN (#{associations.select(:operation_set_id).to_sql})
              )
              UNION ALL
              (
                SELECT
                  assignments.child_id,
                  assignments.parent_id,
                  accessible_operations.operation_set_id AS operation_set_id
                FROM assignments
                INNER JOIN accessible_operations
                ON accessible_operations.child_id = assignments.parent_id
              )
            )
          SELECT accessible_operations.operation_set_id
          FROM accessible_operations
          JOIN policy_elements ops
            ON ops.id = accessible_operations.child_id
          WHERE ops.unique_identifier = ?
          )
        SQL

        associations.where(query, operation)
      end
    end

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
            )
          )

          SELECT parents[1]
          FROM assignments_recursive
          JOIN policy_elements
          ON policy_elements.id = assignments_recursive.child_id
          WHERE #{sanitize_sql_for_conditions(["policy_elements.unique_identifier=:op_id", op_id: operation_id])}
          AND type = 'PolicyMachineStorageAdapter::ActiveRecord::Operation'
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
  end
end
