-----------------------------------------------------
-- File: /02_etl/02_load_customers.sql
-- Purpose: Copy all csv raw data into staging tables
-----------------------------------------------------

BEGIN;

-- Local path on my machine: /Users/jocac/Projects/employee-churn-prediction/

-- Customers dataset

\COPY staging_customers FROM '/Users/jocac/Projects/employee-churn-prediction/data/raw/customers_dataset.csv' DELIMITER ',' CSV HEADER encoding 'UTF-8';

-- Item orders dataset

\COPY staging_item_orders FROM '/Users/jocac/Projects/employee-churn-prediction/data/raw/order_items_dataset.csv' DELIMITER ',' CSV HEADER encoding 'UTF-8';

-- Payments dataset

\COPY staging_payments FROM '/Users/jocac/Projects/employee-churn-prediction/data/raw/order_payments_dataset.csv' DELIMITER ',' CSV HEADER encoding 'UTF-8';

-- Reviews dataset

\COPY staging_reviews FROM '/Users/jocac/Projects/employee-churn-prediction/data/raw/order_reviews_dataset.csv' DELIMITER ',' CSV HEADER encoding 'UTF-8';

-- Orders dataset

\COPY staging_orders FROM '/Users/jocac/Projects/employee-churn-prediction/data/raw/orders_dataset.csv' DELIMITER ',' CSV HEADER encoding 'UTF-8';

-- Product category dataset

\COPY staging_product_category FROM '/Users/jocac/Projects/employee-churn-prediction/data/raw/product_category_name_translation.csv' DELIMITER ',' CSV HEADER encoding 'UTF-8';

-- Products Dataset

\COPY staging_products FROM '/Users/jocac/Projects/employee-churn-prediction/data/raw/products_dataset.csv' DELIMITER ',' CSV HEADER encoding 'UTF-8';

-- Sellers dataset

\COPY staging_sellers FROM '/Users/jocac/Projects/employee-churn-prediction/data/raw/sellers_dataset.csv' DELIMITER ',' CSV HEADER encoding 'UTF-8';

COMMIT;