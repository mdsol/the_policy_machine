class AccessibleObjectsForOperationsFunction < ActiveRecord::Migration[5.2]
  def up
    return unless PolicyMachineStorageAdapter.postgres?

    execute <<~SQL.squish
      CREATE OR REPLACE FUNCTION pm_accessible_objects_for_operations(
        user_id INT,
        operations _TEXT,
        field TEXT,
        filters JSON DEFAULT '{}'
      )
      RETURNS TABLE (
        unique_identifier varchar(255),
        objects _varchar
      ) AS $$
      DECLARE
        filter_key TEXT;
        filter_value TEXT;
        filter_conditions TEXT = '';
      BEGIN
        CREATE TEMP TABLE t_user_attribute_ids (
          child_id INT
        );

        CREATE TEMP TABLE t_operation_set_ids (
          operation_set_id INT,
          object_attribute_id INT
        );

        CREATE TEMP TABLE t_accessible_operations (
          child_id INT,
          operation_set_id INT
        );

        CREATE TEMP TABLE t_operation_sets (
          operation_set_id INT,
          unique_identifier varchar(255)
        );

        SET LOCAL enable_mergejoin TO FALSE;

        WITH RECURSIVE user_attribute_ids AS (
          (
            SELECT
              child_id,
              parent_id
            FROM assignments
            WHERE parent_id = user_id
          )
          UNION ALL
          (
            SELECT
              a.child_id,
              a.parent_id
            FROM
              assignments a
              JOIN user_attribute_ids ua_id ON ua_id.child_id = a.parent_id
          )
        )
        INSERT INTO t_user_attribute_ids
        SELECT child_id FROM user_attribute_ids;

        IF filters IS NOT NULL AND filters::TEXT <> '{}' THEN
          FOR filter_key, filter_value IN
            SELECT * FROM json_each(filters)
          LOOP
            filter_conditions := filter_conditions || filter_key || ' = ' || filter_value || ' AND ';
          END LOOP;

          /* Chomp trailing AND */
          filter_conditions := left(filter_conditions, -4);
          /* Replace double quotes */
          filter_conditions := replace(filter_conditions, '"', '''');

          EXECUTE format(
            'DELETE FROM t_user_attribute_ids ' ||
            'WHERE child_id NOT IN (SELECT id FROM policy_elements WHERE %s)',
            filter_conditions
          );
        END IF;

        INSERT INTO t_operation_set_ids
        SELECT
          pea.operation_set_id,
          pea.object_attribute_id
        FROM
          policy_element_associations pea
          JOIN t_user_attribute_ids t ON t.child_id = pea.user_attribute_id;

        WITH RECURSIVE accessible_operations AS (
          (
            SELECT
              child_id,
              parent_id AS operation_set_id
            FROM assignments
            WHERE parent_id IN (SELECT operation_set_id FROM t_operation_set_ids)
          )
          UNION ALL
          (
            SELECT
              a.child_id,
              op.operation_set_id AS operation_set_id
            FROM
              assignments a
              JOIN accessible_operations op ON op.child_id = a.parent_id
          )
        )
        INSERT INTO t_accessible_operations
        SELECT * FROM accessible_operations;

        INSERT INTO t_operation_sets
        SELECT DISTINCT ao.operation_set_id, ops.unique_identifier
          FROM
            t_accessible_operations ao
            JOIN policy_elements ops ON ops.id = ao.child_id
          WHERE ops.unique_identifier = ANY (operations);

        RETURN QUERY EXECUTE
        format(
          'SELECT os.unique_identifier, array_agg(DISTINCT pe.%I) AS objects ' ||
          'FROM ' ||
          '  t_operation_set_ids os_id ' ||
          '  JOIN t_operation_sets os ON os.operation_set_id = os_id.operation_set_id ' ||
          '  JOIN policy_elements pe ON pe.id = os_id.object_attribute_id ' ||
          'WHERE pe."type" = ''PolicyMachineStorageAdapter::ActiveRecord::Object'' ' ||
          'GROUP BY os.unique_identifier',
          field
        );

        DROP TABLE IF EXISTS t_user_attribute_ids;
        DROP TABLE IF EXISTS t_operation_set_ids;
        DROP TABLE IF EXISTS t_accessible_operations;
        DROP TABLE IF EXISTS t_operation_sets;

        RETURN;
      END;
      $$ LANGUAGE plpgsql;
    SQL
  end

  def down
    execute 'DROP FUNCTION IF EXISTS pm_accessible_objects_for_operations'
  end
end
