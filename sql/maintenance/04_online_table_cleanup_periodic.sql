------------------------------------------------------------------------------
-- Time-based cleanup for online serving buffer tables only.
-- Does NOT touch seller_order_history_base (or rejected_* audit tables).
--
-- Bind :retention_days as integer (e.g. 7 = delete rows older than 7 days).
-- FK-safe delete order: children before parents for final_user_orders subtree.
------------------------------------------------------------------------------

DELETE FROM users_feature_engineering
WHERE ingested_at < (CURRENT_TIMESTAMP - (:retention_days * INTERVAL '1 day'));

DELETE FROM final_user_payments
WHERE ingested_at < (CURRENT_TIMESTAMP - (:retention_days * INTERVAL '1 day'));

DELETE FROM final_user_order_items
WHERE ingested_at < (CURRENT_TIMESTAMP - (:retention_days * INTERVAL '1 day'));

DELETE FROM final_user_orders
WHERE ingested_at < (CURRENT_TIMESTAMP - (:retention_days * INTERVAL '1 day'));

DELETE FROM staging_user_payments
WHERE ingested_at < (CURRENT_TIMESTAMP - (:retention_days * INTERVAL '1 day'));

DELETE FROM staging_user_order_items
WHERE ingested_at < (CURRENT_TIMESTAMP - (:retention_days * INTERVAL '1 day'));

DELETE FROM staging_user_orders
WHERE ingested_at < (CURRENT_TIMESTAMP - (:retention_days * INTERVAL '1 day'));
