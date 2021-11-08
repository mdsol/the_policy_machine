module PolicyMachineStorageAdapter
  class ActiveRecord
    class PolicyElement

      # given a list of operation set ids
      # return row hashes of operation_set_id, unique_identifier pairs
      # representing all operations contained by the given operation set ids
      # optionally can give a list of operation names to filter by
      def self.operations_for_operation_sets(operation_set_ids, operation_names = nil)
        query = <<~SQL
          WITH RECURSIVE accessible_operations AS (
            (
              SELECT
                child_id,
                parent_id,
                parent_id AS operation_set_id
              FROM assignments
              WHERE parent_id IN (?)
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

          SELECT DISTINCT accessible_operations.operation_set_id, ops.unique_identifier
          FROM accessible_operations
          JOIN policy_elements ops
            ON ops.id = accessible_operations.child_id
        SQL

        sanitize_arg = [query, operation_set_ids]

        if operation_names
          query << "WHERE ops.unique_identifier IN (?)"
          sanitize_arg << operation_names
        else
          type = PolicyMachineStorageAdapter::ActiveRecord.class_for_type('operation').name
          query << "WHERE ops.type = '#{type}'"
        end

        sanitized_query = sanitize_sql_for_assignment(sanitize_arg)

        # gives pairs of (opset_id, operation) representing all operations contained by an operation set
        # accounts for any nested operation sets
        #
        # e.g:
        #
        #            opset_123    opset_789
        #             /     \      /     \
        #      opset_456   operation2   operation3
        #           /
        #   operation1
        #
        # will result in:
        #   (123, operation1)
        #   (123, operation2)
        #   (789, operation2)
        #   (789, operation3)
        #
        # NOTE:
        # actual output will be row hashes like:
        # [
        #   { 'operation_set_id' => 123, 'unique_identifier' => 'operation1' },
        #   { 'operation_set_id' => 123, 'unique_identifier' => 'operation2' },
        #   { 'operation_set_id' => 789, 'unique_identifier' => 'operation2' },
        #   { 'operation_set_id' => 789, 'unique_identifier' => 'operation3' },
        # ]
        connection.execute(sanitized_query)
      end

      def self.accessible_objects_for_operations(user_id, operation_names, options)
        field = options[:fields].first
        filters = options.dig(:filters, :user_attributes) || {}

        query = sanitize_sql_for_assignment([
          'SELECT * FROM pm_accessible_objects_for_operations(?,?,?,?)',
          user_id,
          PG::TextEncoder::Array.new.encode(operation_names),
          field,
          JSON.dump(filters)
        ])

        # [
        #   { 'unique_identifier' => 'op1', 'objects' => '{obj1,obj2,obj3}' },
        #   { 'unique_identifier' => 'op2', 'objects' => '{obj1,obj2,obj3}' },
        # ]
        result = connection.execute(query).to_a

        # {
        #    'op1' => [{ :field => 'obj1' }, { :field => 'obj2' }, { :field => 'obj3' }],
        #    'op2' => [{ :field => 'obj2' }, { :field => 'obj3' }, { :field => 'obj4' }],
        # }
        decoder = PG::TextDecoder::Array.new
        result.each_with_object({}) do |result_hash, output|
          objects = decoder.decode(result_hash['objects'])
          key = result_hash['unique_identifier']
          output[key] = objects.map { |o| { field => o }}
        end
      end
    end

    class PolicyElementAssociation
      def self.scoped_accessible_objects(associations, root_id:, filters: {})
        pea_ids = associations.pluck(:id)
        return PolicyElement.none if pea_ids.empty?

        # This query determines which objects are (1) privileged given a
        # set of PEAs and (2) within the scope of the given root object.
        # A brief explanation of the CTEs follows:
        # 'ancestor_scope' - the set of objects within the scope of the
        #                    given root object
        # 'leaf_ancestors' - the subset of 'ancestor_scope' that are
        #                    terminal nodes in the graph
        # 'leaf_descendants' - the set of objects that cascade access
        #                      to 'leaf_ancestors'
        # 'accessible_leaf_descendants' - the set of objects that
        #                                 (1) cascade access to
        #                                 'leaf_descendants' and
        #                                 (2) are privileged by any of
        #                                 the given set of PEAs
        # 'accessible_ancestors' - the full set of objects that cascade
        #                          from 'accessible_leaf_descendants'
        # The final statement intersects the set of 'ancestor_scope' and
        # 'accessible_ancestors', meaning it returns the full set of
        # objects that are (1) privileged given the set of PEAs and
        # (2) within the scope of the given root object
        query = <<-SQL
          id IN (
            WITH RECURSIVE ancestor_scope AS (
              SELECT
                  id AS child_id,
                  id AS parent_id
              FROM policy_elements
              WHERE id = ?

              UNION ALL

              SELECT
                  assignments.child_id,
                  assignments.parent_id
              FROM assignments
              JOIN ancestor_scope
                  ON assignments.child_id = ancestor_scope.parent_id
            ),

            leaf_ancestors AS (
              SELECT DISTINCT
                  ancestor_scope.parent_id AS parent_id
              FROM ancestor_scope
              LEFT OUTER JOIN assignments
                  ON ancestor_scope.parent_id = assignments.child_id
              WHERE assignments.child_id IS NULL
            ),

            leaf_descendants AS (
              SELECT
                  parent_id,
                  parent_id AS child_id
              FROM leaf_ancestors

              UNION ALL

              SELECT
                  assignments.parent_id,
                  assignments.child_id
              FROM assignments
              JOIN leaf_descendants
                  ON leaf_descendants.child_id = assignments.parent_id
            ),

            accessible_leaf_descendants AS (
              SELECT DISTINCT
                  leaf_descendants.child_id
              FROM leaf_descendants
              JOIN policy_element_associations peas
                  ON peas.object_attribute_id = leaf_descendants.child_id
              WHERE peas.id IN (?)
            ),

            accessible_ancestors AS (
              SELECT
                  child_id,
                  child_id AS parent_id
              FROM accessible_leaf_descendants

              UNION ALL

              SELECT
                  a.child_id,
                  a.parent_id
              FROM assignments a
              JOIN accessible_ancestors d
                  ON a.child_id = d.parent_id
            )

            SELECT
                accessible_ancestors.parent_id
            FROM accessible_ancestors
            JOIN ancestor_scope
                ON ancestor_scope.parent_id = accessible_ancestors.parent_id
          )
        SQL

        PolicyElement.where(query, root_id, pea_ids).where(filters)
      end

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
        PolicyElement.where(ancestors_of_query, [*element_or_scope].map(&:id))
      end

      def self.ancestors_of_with_pluck(element_or_scope)
        PolicyElement.where(ancestors_of_query, element_or_scope.pluck(:id))
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

      private

      def self.ancestors_of_query
        <<-SQL
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

    private

    # Convert array to '{element1,element2,element3}'
    def self.array_to_string(array)
      "{#{array.join(',')}}"
    end
  end
end
