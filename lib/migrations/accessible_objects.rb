class AccessibleObjectsForOperationsFunction < ActiveRecord::Migration[5.2]
  def up
    return unless PolicyMachineStorageAdapter.postgres?

    execute <<~SQL.squish
      CREATE OR REPLACE FUNCTION pm_accessible_objects(
        user_id INT,
        operation TEXT,
        field TEXT,
        direct_only BOOLEAN DEFAULT NULL,
        filters JSON DEFAULT '{}',
        includes_key TEXT DEFAULT NULL,
        includes_value TEXT DEFAULT NULL
      )
      RETURNS TABLE (
        objects TEXT
      ) AS $$
      DECLARE
        filter_key TEXT;
        filter_value TEXT;
        filter_conditions TEXT = '';
        q_user_attributes TEXT;
        q_objects TEXT;
      BEGIN
        CREATE TEMP TABLE t_user_attributes (
          user_attribute_id INT
        );

        CREATE TEMP TABLE t_associations (
          operation_set_id INT
        );

        CREATE TEMP TABLE t_accessible_operations (
          operation_set_id INT
        );

        CREATE TEMP TABLE t_filtered_associations (
          object_attribute_id INT
        );

        CREATE TEMP TABLE t_assigned_objects (
          id INT
        );

        SET LOCAL enable_mergejoin TO FALSE;

        q_user_attributes :=
        'WITH RECURSIVE assignments_recursive AS (
          (
            SELECT child_id, parent_id
            FROM assignments
            WHERE parent_id = %L
          )
          UNION ALL
          (
            SELECT a.child_id, a.parent_id
            FROM assignments a
            INNER JOIN assignments_recursive ar
            ON ar.child_id = a.parent_id
          )
        )
        INSERT INTO t_user_attributes
        SELECT child_id AS user_attribute_id
        FROM assignments_recursive';

        IF filters IS NOT NULL AND filters::TEXT <> '{}' THEN
          FOR filter_key, filter_value IN
            SELECT * FROM json_each(filters)
          LOOP
            filter_conditions := filter_conditions || filter_key || ' = ' || filter_value || ' AND ';
          END LOOP;

          /* Chomp trailing AND */
          filter_conditions := left(filter_conditions, -5);
          /* Replace double quotes */
          filter_conditions := replace(filter_conditions, '"', '''');

          q_user_attributes :=  q_user_attributes || format('
            WHERE child_id IN (SELECT id FROM policy_elements WHERE %s)',
            filter_conditions
          );
        END IF;

        EXECUTE format(q_user_attributes, user_id);
        INSERT INTO t_user_attributes VALUES (user_id);

        INSERT INTO t_associations
        SELECT
          operation_set_id
        FROM
          policy_element_associations
          JOIN t_user_attributes USING (user_attribute_id);

        WITH RECURSIVE accessible_operations AS (
          (
            SELECT
              child_id,
              parent_id AS operation_set_id
            FROM
              assignments a
              JOIN t_associations ta ON ta.operation_set_id = a.parent_id
          )
          UNION /* Remove dupes more efficiently than DISTINCT */
          (
            SELECT
              a.child_id,
              a.parent_id AS operation_set_id
            FROM assignments a
            INNER JOIN accessible_operations ao
              ON ao.child_id = a.parent_id
          )
        )
        INSERT INTO t_accessible_operations
        SELECT operation_set_id
        FROM accessible_operations
        WHERE child_id = (SELECT id FROM policy_elements WHERE unique_identifier = operation);

        INSERT INTO t_filtered_associations
        SELECT object_attribute_id
        FROM policy_element_associations
        WHERE
          user_attribute_id IN (SELECT user_attribute_id FROM t_user_attributes)
          AND operation_set_id IN (SELECT operation_set_id FROM t_accessible_operations);

        INSERT INTO t_assigned_objects
        SELECT id
        FROM policy_elements
        WHERE
          id IN (SELECT object_attribute_id FROM t_filtered_associations)
          AND "type" = 'PolicyMachineStorageAdapter::ActiveRecord::Object';

        /* ancestor assignments */
        IF COALESCE(direct_only, FALSE) = FALSE THEN
          WITH RECURSIVE assignments_recursive AS (
            (
              SELECT a.parent_id, a.child_id
              FROM
                assignments a
                JOIN t_filtered_associations tfa ON tfa.object_attribute_id = a.child_id
            )
            UNION
            (
              SELECT a.parent_id, a.child_id
              FROM assignments a
              INNER JOIN assignments_recursive ar
              ON ar.parent_id = a.child_id
            )
          )
          INSERT INTO t_assigned_objects
          SELECT ar.parent_id
          FROM assignments_recursive ar;
        END IF;

        q_objects := format(
          'SELECT pe.%I::TEXT ' ||
          'FROM ' ||
          '  policy_elements pe ' ||
          '  JOIN t_assigned_objects USING (id) ' ||
          'WHERE pe."type" = ''PolicyMachineStorageAdapter::ActiveRecord::Object''',
          field
        );

        IF includes_key IS NOT NULL AND includes_value IS NOT NULL THEN
          q_objects := q_objects || format(' AND %I LIKE ''%%%s%%''', includes_key, includes_value);
        END IF;

        RETURN query EXECUTE q_objects;

        DROP TABLE IF EXISTS t_user_attributes;
        DROP TABLE IF EXISTS t_associations;
        DROP TABLE IF EXISTS t_accessible_operations;
        DROP TABLE IF EXISTS t_filtered_associations;
        DROP TABLE IF EXISTS t_assigned_objects;

        RETURN;
      END;
      $$ LANGUAGE plpgsql;
    SQL
  end

  def down
    execute 'DROP FUNCTION IF EXISTS pm_accessible_objects_for_operations' if PolicyMachineStorageAdapter.postgres?
  end
end
