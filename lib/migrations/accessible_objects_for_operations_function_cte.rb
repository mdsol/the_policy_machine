class AccessibleObjectsForOperationsFunctionCte < ActiveRecord::Migration[5.2]
  def up
    return unless PolicyMachineStorageAdapter.postgres?

    execute <<~SQL.squish
      CREATE OR REPLACE FUNCTION pm_accessible_objects_for_operations_cte(
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
        mergejoin TEXT;
        filter_key TEXT;
        filter_value TEXT;
        filter_conditions TEXT = '';
        user_attribute_table TEXT = 'user_attribute_ids';
        query_text TEXT;
      BEGIN
        query_text := '
        WITH RECURSIVE user_attribute_ids AS (
          (
            SELECT
              child_id,
              parent_id
            FROM assignments
            WHERE parent_id = $1
          )
          UNION ALL
          (
            SELECT
              a.child_id,
              a.parent_id
            FROM assignments a
            JOIN user_attribute_ids ua_id
              ON ua_id.child_id = a.parent_id
          )
        ),';

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

          query_text := query_text || format('
          user_attribute_filtered_ids AS (
            SELECT ua.child_id
            FROM user_attribute_ids ua
            JOIN policy_elements pe
              ON pe.id = ua.child_id
            WHERE %s
          ),', filter_conditions);

          user_attribute_table := 'user_attribute_filtered_ids';
        END IF;

        query_text := query_text || '
        operation_set_ids AS (
          SELECT
            operation_set_id,
            object_attribute_id
          FROM policy_element_associations
          WHERE user_attribute_id IN (SELECT child_id FROM %I)
        ),
        accessible_operations AS (
          (
            SELECT
              child_id,
              parent_id AS operation_set_id
            FROM assignments
            WHERE parent_id IN (SELECT operation_set_id FROM operation_set_ids)
          )
          UNION ALL
          (
            SELECT
              a.child_id,
              op.operation_set_id AS operation_set_id
            FROM assignments a
            JOIN accessible_operations op
              ON op.child_id = a.parent_id
          )
        ),
        operation_sets AS (
          SELECT DISTINCT ao.operation_set_id, ops.unique_identifier
          FROM accessible_operations ao
          JOIN policy_elements ops
            ON ops.id = ao.child_id
          WHERE ops.unique_identifier = ANY ($2)
        ),
        operation_objects AS (
          SELECT
            os.unique_identifier,
            array_remove(array_agg(
              (
                SELECT pe.%I
                FROM policy_elements pe
                WHERE
                  pe.id = os_id.object_attribute_id
                  AND "type" = ''PolicyMachineStorageAdapter::ActiveRecord::Object''
              )
            ), NULL) AS objects
          FROM
            operation_set_ids os_id
            JOIN operation_sets os ON os.operation_set_id = os_id.operation_set_id
          GROUP BY os.unique_identifier
        )
        SELECT
          unique_identifier,
          ARRAY(SELECT DISTINCT o FROM UNNEST(objects) AS a(o)) as objects
        FROM operation_objects';

        mergejoin := (SELECT setting FROM pg_settings s WHERE s."name" = 'enable_mergejoin');
        SET LOCAL enable_mergejoin TO FALSE;

        RETURN QUERY EXECUTE format(
          query_text,
          user_attribute_table,
          field
        ) USING
          user_id,
          operations;

        EXECUTE format('SET LOCAL enable_mergejoin TO %s', mergejoin);
      END;
      $$ LANGUAGE plpgsql;
    SQL
  end

  def down
    execute 'DROP FUNCTION IF EXISTS pm_accessible_objects_for_operations_cte'
  end
end
