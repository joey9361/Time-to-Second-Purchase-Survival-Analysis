------------------------------------------------------------------------------
-- Check whether a request_id has any rejected rows.
-- Bind :request_id (TEXT/VARCHAR), e.g. {"request_id": "req_000001"}.
--
-- Returns:
-- - per-table rejected row counts
-- - total_rejected_rows
-- - any_rejected_rows (boolean gate flag)
------------------------------------------------------------------------------
WITH rejected_counts AS (
    SELECT
        COUNT(*) FILTER (WHERE source_table = 'rejected_user_orders') AS rejected_orders_count,
        COUNT(*) FILTER (WHERE source_table = 'rejected_user_payments') AS rejected_payments_count,
        COUNT(*) FILTER (WHERE source_table = 'rejected_user_order_items') AS rejected_items_count
    FROM (
        SELECT 'rejected_user_orders' AS source_table
        FROM rejected_user_orders
        WHERE request_id = :request_id

        UNION ALL

        SELECT 'rejected_user_payments' AS source_table
        FROM rejected_user_payments
        WHERE request_id = :request_id

        UNION ALL

        SELECT 'rejected_user_order_items' AS source_table
        FROM rejected_user_order_items
        WHERE request_id = :request_id
    ) AS all_rejected_rows
)
SELECT
    rejected_orders_count,
    rejected_payments_count,
    rejected_items_count,
    (rejected_orders_count + rejected_payments_count + rejected_items_count) AS total_rejected_rows,
    (rejected_orders_count + rejected_payments_count + rejected_items_count) > 0 AS any_rejected_rows
FROM rejected_counts;
