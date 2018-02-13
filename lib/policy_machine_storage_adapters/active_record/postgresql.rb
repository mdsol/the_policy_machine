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

      def self.ancestors_filtered_by_policy_element_associations(element, policy_element_association_ids)
        query = <<-SQL
          id IN (
            WITH RECURSIVE assignments_recursive(parent_id, child_id, matching_policy_element_association_id) AS (
              (
                SELECT parent_id, child_id, policy_element_associations.id
                FROM assignments
                LEFT OUTER JOIN policy_element_associations 
                  ON assignments.parent_id = policy_element_associations.object_attribute_id AND
                    policy_element_associations.id IN (:policy_element_association_ids)
                WHERE child_id = :accessible_scope_id
              )
              UNION
              (
                SELECT assignments.parent_id, assignments.child_id, policy_element_associations.id 
                FROM assignments
                INNER JOIN assignments_recursive ON assignments_recursive.parent_id = assignments.child_id
                LEFT OUTER JOIN policy_element_associations
                  ON assignments_recursive.parent_id = policy_element_associations.object_attribute_id AND 
                    policy_element_associations.id IN (:policy_element_association_ids)
                WHERE assignments_recursive.matching_policy_element_association_id IS NULL 
              )
            )
          
            SELECT assignments_recursive.child_id
            FROM assignments_recursive
            WHERE matching_policy_element_association_id IS NOT NULL
          )
        SQL

        PolicyElement.where(query,
          accessible_scope_id: element.id,
          policy_element_association_ids: policy_element_association_ids)
      end

      def self.accessible_ancestors_filtered_by_policy_element_associations_and_object_descendants_or_something(element, policy_element_association_ids)
        # For test set, pea_ids = (1, 2, 3, 4, 5, 6, 7, 8, 9, 10), child_id = 61
        # for sandbox set, child_id = 23288558, pea_ids = (13220049, 13220052, 13220053, 13220131, 13220134, 13220135, 13220136, 13220137, 13220138, 13220139)
        # NOTE: The sandbox set is an old local copy for me, the values may not be the same on live sandbox.
        query = <<-SQL
          id IN (
            WITH RECURSIVE assignments_recursive(parent_id, child_id, path, matching_policy_element_association_id) AS (
              (
                SELECT asg1.parent_id, asg1.child_id, ARRAY[asg1.parent_id], pea.id
                FROM assignments AS asg1
                LEFT OUTER JOIN policy_element_associations AS pea 
                ON (pea.id IN (:policy_element_association_ids) AND asg1.parent_id = pea.object_attribute_id) 
                  OR pea.id IN (
                    WITH RECURSIVE child_assignments_recursive(child_id, parent_id, path, cycle, matching_policy_element_association_id) AS (
                      (
                        SELECT afc.child_id, afc.parent_id, ARRAY[afc.parent_id], afc.child_id = afc.parent_id, policy_element_associations.id
                        FROM assignments AS afc
                        LEFT OUTER JOIN policy_element_associations ON policy_element_associations.id IN (:policy_element_association_ids) AND afc.child_id = policy_element_associations.object_attribute_id
                        WHERE afc.parent_id = asg1.parent_id
                      )
                      UNION ALL
                      (
                        SELECT afc.child_id, afc.parent_id, child_assignments_recursive.child_id || path, afc.child_id = ANY(PATH), policy_element_associations.id
                        FROM assignments AS afc
                        JOIN child_assignments_recursive ON child_assignments_recursive.child_id = afc.parent_id
                        LEFT OUTER JOIN policy_element_associations ON policy_element_associations.id IN (:policy_element_association_ids) AND afc.child_id = policy_element_associations.object_attribute_id
                        WHERE child_assignments_recursive.matching_policy_element_association_id IS NULL AND NOT cycle
                      )
                    )
            
                    SELECT child_assignments_recursive.matching_policy_element_association_id
                    FROM child_assignments_recursive
                    WHERE child_assignments_recursive.matching_policy_element_association_id IS NOT NULL
                    LIMIT 1
                  )
                WHERE child_id = :accessible_scope_id
              )
              UNION
              (
                SELECT asg.parent_id, asg.child_id, path || assignments_recursive.parent_id, pea.id
                FROM assignments AS asg
                JOIN assignments_recursive ON assignments_recursive.parent_id = asg.child_id
                LEFT OUTER JOIN policy_element_associations AS pea 
                ON (pea.id IN (:policy_element_association_ids) AND asg.parent_id = pea.object_attribute_id) 
                  OR pea.id IN (
                    WITH RECURSIVE child_assignments_recursive(child_id, parent_id, path, cycle, matching_policy_element_association_id) AS (
                      (
                        SELECT afc.child_id, afc.parent_id, ARRAY[afc.parent_id], afc.child_id = afc.parent_id, policy_element_associations.id
                        FROM assignments AS afc
                        LEFT OUTER JOIN policy_element_associations ON policy_element_associations.id IN (:policy_element_association_ids) AND afc.child_id = policy_element_associations.object_attribute_id
                        WHERE afc.parent_id = asg.parent_id AND afc.child_id != ANY(assignments_recursive.path)
                      )
                      UNION ALL
                      (
                        SELECT afc.child_id, afc.parent_id, child_assignments_recursive.child_id || path, afc.child_id = ANY(path), policy_element_associations.id
                        FROM assignments AS afc
                        JOIN child_assignments_recursive ON child_assignments_recursive.child_id = afc.parent_id AND afc.parent_id != ANY(assignments_recursive.path)
                        LEFT OUTER JOIN policy_element_associations ON policy_element_associations.id IN (:policy_element_association_ids) AND afc.child_id = policy_element_associations.object_attribute_id
                        WHERE child_assignments_recursive.matching_policy_element_association_id IS NULL AND NOT cycle
                      )
                    )
            
                    SELECT child_assignments_recursive.matching_policy_element_association_id
                    FROM child_assignments_recursive
                    WHERE child_assignments_recursive.matching_policy_element_association_id IS NOT NULL
                    LIMIT 1
                  )
                WHERE assignments_recursive.matching_policy_element_association_id IS NULL
              )
            )
            SELECT assignments_recursive.parent_id
            FROM assignments_recursive
            WHERE matching_policy_element_association_id IS NOT NULL;	
          )
        SQL

        PolicyElement.where(query,
          accessible_scope_id: element.id,
          policy_element_association_ids: policy_element_association_ids)
      end

      def any_ancestor_cycles?(element)
        query = <<-SQL
          WITH RECURSIVE assignments_recursive(rp, rc, path, cycle) AS (
            (
              SELECT 
                parent_id,
                child_id,
                ARRAY[child_id],
                parent_id = child_id
              FROM assignments
              WHERE parent_id = :element_id
            ) UNION ALL (
              SELECT
                parent_id, child_id, rp || path, parent_id = ANY(path)
              FROM assignments
              JOIN assignments_recursive ON child_id = path[1]
              WHERE NOT cycle
            )
          )
            SELECT rc.id
            FROM assignments_recursive
            WHERE cycle
        SQL

        PolicyElement.where(query, element_id: element.id)
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
