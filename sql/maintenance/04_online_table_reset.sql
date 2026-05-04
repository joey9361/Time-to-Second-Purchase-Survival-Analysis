-- Drop all tables in the online staging schema
DROP TABLE IF EXISTS staging_user_orders CASCADE;
DROP TABLE IF EXISTS staging_user_order_items CASCADE;
DROP TABLE IF EXISTS staging_user_payments CASCADE;

-- Drop all tables in the online final schema
DROP TABLE IF EXISTS final_user_orders CASCADE;
DROP TABLE IF EXISTS final_user_order_items CASCADE;
DROP TABLE IF EXISTS final_user_payments CASCADE;
DROP TABLE IF EXISTS users_feature_engineering CASCADE;