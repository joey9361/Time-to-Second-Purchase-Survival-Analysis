----------------------------------------------------------------------------
-- File: 'sql/02_load/02_transform.sql
-- Purpose: Transform raw data tables into correct format and data type for finals tables
-- Handle errors, perform validation
----------------------------------------------------------------------------

BEGIN;
------------------
-- Orders dataset
------------------

WITH deduplicate_orders AS(
    SELECT DISTINCT ON (order_id)
        order_id,
        customer_id,
        order_status,
        purchase_date,
        order_approval_date,
        delivered_carrier_date,
        delivered_customer_date,
        estimated_delivery_date
    FROM staging_orders
    WHERE order_id IS NOT NULL
    AND customer_id IS NOT NULL
    AND purchase_date IS NOT NULL

    ORDER BY order_id
)
INSERT INTO final_orders(
    order_id,
    customer_id,
    order_status,
    purchase_date,
    order_approval_date,
    delivered_carrier_date,
    delivered_customer_date,
    estimated_delivery_date
)
SELECT * FROM (
    SELECT
        order_id::VARCHAR(50),
        customer_id::varchar(50),
        COALESCE(order_status::VARCHAR(25), 'delivered'), -- Default to delivered if NULL value

        -- Make sure format for date is correct else NULL
        CASE WHEN purchase_date ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$' THEN purchase_date::TIMESTAMP::DATE
        ELSE NULL
        END AS purchase_date,

        CASE WHEN order_approval_date ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$' THEN order_approval_date::TIMESTAMP::DATE
        ELSE NULL
        END AS order_approval_date,

        CASE WHEN delivered_carrier_date ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$' THEN delivered_carrier_date::TIMESTAMP::DATE
        ELSE NULL
        END AS delivered_carrier_date,

        CASE WHEN delivered_customer_date ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$' THEN delivered_customer_date::TIMESTAMP::DATE
        ELSE NULL
        END AS delivered_customer_date,

        CASE WHEN estimated_delivery_date ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$' THEN estimated_delivery_date::TIMESTAMP::DATE
        ELSE NULL
        END AS estimated_delivery_date
    FROM deduplicate_orders
) AS processed_orders
WHERE purchase_date IS NOT NULL;

---------------------------
-- Product category dataset
---------------------------

WITH deduplicate_prod_category AS (
    SELECT DISTINCT ON (product_category)
        product_category,
        product_category_english
    FROM staging_product_category
    WHERE product_category IS NOT NULL
    ORDER BY product_category
)
INSERT INTO final_product_category(
    product_category,
    product_category_english
)
SELECT
    product_category,
    product_category_english
FROM deduplicate_prod_category;

-- Manually insert an unknown category for if a product has a null category
INSERT INTO final_product_category(
    product_category,
    product_category_english
) VALUES ('unknown', 'unknown');

--------------------
-- Products dataset
--------------------

WITH deduplicate_products AS (
    SELECT DISTINCT ON (product_id)
        product_id,
        product_category_name,
        product_name_length,
        product_description_length,
        product_photos_qty,
        product_weight_g,
        product_length_cm,
        product_height_cm,
        product_width_cm
    FROM staging_products
    WHERE product_id IS NOT NULL
    ORDER BY product_id
)
INSERT INTO final_products(
    product_id,
    product_category_name,
    product_name_length,
    product_description_length,
    product_photos_qty,
    product_weight_g,
    product_length_cm,
    product_height_cm,
    product_width_cm
)
SELECT * FROM (
    SELECT
        product_id::VARCHAR(50),
        COALESCE(product_category_name, 'unknown') as product_category_name, -- All null categories listed as unknown

        -- Make sure all text is of an integer before casting else NULL
        CASE WHEN product_name_length ~ '^[0-9]+$' THEN product_name_length::INTEGER
        ELSE NULL END AS product_name_length,

        CASE WHEN product_description_length ~ '^[0-9]+$' THEN product_description_length::INTEGER
        ELSE NULL END AS product_description_length,

        CASE WHEN product_photos_qty ~ '^[0-9]+$' THEN product_photos_qty::INTEGER
        ELSE NULL END AS product_photos_qty,

        CASE WHEN product_weight_g ~ '^[0-9]+$' THEN product_weight_g::INTEGER
        ELSE NULL END AS product_weight_g,

        CASE WHEN product_length_cm ~ '^[0-9]+$' THEN product_length_cm::INTEGER
        ELSE NULL END AS product_length_cm,

        CASE WHEN product_height_cm ~ '^[0-9]+$' THEN product_height_cm::INTEGER
        ELSE NULL END AS product_height_cm,

        CASE WHEN product_width_cm ~ '^[0-9]+$' THEN product_width_cm::INTEGER
        ELSE NULL END AS product_width_cm
    FROM deduplicate_products
) AS processed_products
WHERE product_category_name in (SELECT product_category FROM final_product_category); -- Make sure product category is in product_category table

-------------------
-- Sellers dataset
-------------------

WITH deduplicate_sellers AS (
    SELECT DISTINCT ON (seller_id)
        seller_id,
        zip_code,
        seller_city,
        seller_state
    FROM staging_sellers
    WHERE seller_id IS NOT NULL
    ORDER BY seller_id
)
INSERT INTO final_sellers(
    seller_id,
    zip_code,
    seller_city,
    seller_state
)
SELECT
    seller_id::VARCHAR(50),
    -- Make sure zip code is a number before casting
    CASE WHEN zip_code ~ '^[0-9]+$' THEN zip_code::INTEGER
    ELSE NULL END AS zip_code,

    seller_city::VARCHAR(50),
    seller_state::VARCHAR(3)
FROM deduplicate_sellers;

-------------------
-- Item_orders dataset
-------------------

WITH deduplicate_order_items AS (
    SELECT DISTINCT ON (order_id, item_id) -- remove duplicate items of the same order
        order_id,
        item_id,
        product_id,
        seller_id,
        shipping_limit_date,
        price,
        freight_value
    FROM staging_item_orders
    -- remove important NULL values
    WHERE order_id IS NOT NULL
    AND item_id IS NOT NULL
    AND product_id IS NOT NULL
    AND shipping_limit_date IS NOT NULL
    AND seller_id IS NOT NULL
    AND price IS NOT NULL
    ORDER BY order_id, item_id
)
INSERT INTO final_item_orders(
    order_id,
    item_id,
    product_id,
    seller_id,
    shipping_limit_date,
    price,
    freight_value
)
SELECT * FROM (
    SELECT 
        order_id::VARCHAR(50),
        item_id::INTEGER,
        product_id::VARCHAR(50),
        seller_id::VARCHAR(50),
        -- Safely cast date if correct format
        CASE
            WHEN shipping_limit_date ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$' THEN shipping_limit_date::TIMESTAMP::DATE
            ELSE NULL
            END AS shipping_limit_date,
        -- Safely cast price if correct format and non zero
        CASE
            WHEN price ~ '^[0-9]+\.[0-9]{2}$' AND price::FLOAT::INTEGER != 0 THEN price::NUMERIC(10,2)
            ELSE NULL
            END AS price,
        --Safely cast freight value if correct format
        CASE 
            WHEN freight_value ~ '^[0-9]+\.[0-9]+$' THEN freight_value::NUMERIC(10,2)
            ELSE NULL 
            END AS freight_value
    FROM deduplicate_order_items
) AS processed_item_orders
-- Remove NULL values imputed because of incorrect format 
WHERE shipping_limit_date IS NOT NULL
AND price IS NOT NULL
-- Make sure order, product, seller id exists in orders table
AND order_id in (SELECT order_id FROM final_orders) 
AND seller_id in (SELECT seller_id FROM final_sellers)
AND product_id in (SELECT product_id FROM final_products); 

--------------------
-- Customers dataset
--------------------

WITH deduplicate_id AS (
    SELECT DISTINCT ON (customer_id) -- Remove duplicate id's
        customer_id,
        customer_unique_id,
        zip_code,
        city,
        customer_state
    FROM staging_customers
    -- Remove NULL ID's
    WHERE customer_id IS NOT NULL 
    AND customer_unique_id IS NOT NULL
    ORDER BY customer_id, customer_unique_id
)
INSERT INTO final_customers(
    customer_id,
    customer_unique_id,
    zip_code,
    city,
    customer_state
)
SELECT 
    -- Type cast Text to appropriate varchar
    customer_id::VARCHAR(50) AS customer_id,
    customer_unique_id::VARCHAR(50) AS customer_unique_id,
    -- Safely type cast zip codes to integers
    CASE 
        WHEN zip_code ~ '^[0-9]+$' THEN zip_code::INTEGER
        ELSE NULL
    END AS zip_code,
    
    city::VARCHAR(50) AS city,
    customer_state::VARCHAR(3) AS customer_state
FROM deduplicate_id
WHERE customer_id in (SELECT customer_id FROM final_orders); -- Make sure order id exists in orders table

---------------------------
-- Order Payments dataset
---------------------------

-- Remove exact duplicate rows, expecting duplicate ids but of different payment_sequential
WITH deduplicate_payment_seq AS (
    SELECT DISTINCT ON (order_id, payment_sequential)
        order_id AS id,
        payment_sequential AS seq,
        payment_type,
        num_installments,
        payment_value
    FROM staging_payments
    WHERE order_id IS NOT NULL
    AND payment_value IS NOT NULL
    ORDER BY order_id, payment_sequential
)
INSERT INTO final_payments(
    order_id,
    payment_sequential,
    payment_type,
    num_installments,
    payment_value
)
SELECT * FROM ( -- Subquery to handle NULL value replacements in outer select
    SELECT
        id::VARCHAR(50) AS id,
        ROW_NUMBER() OVER (PARTITION BY id) AS seq,
        -- Coalesce because values could be null, so assign default values otherwise cast
        COALESCE(payment_type::VARCHAR(25), -- Assign voucher by default if more than 1 sequential payment per order
                CASE WHEN count(*) OVER (PARTITION BY id) > 1 THEN 'voucher' -- Check if an order id occurs more than 1 time  
                ELSE 'credit_card' END 
                ) AS payment_type,
        COALESCE(num_installments::INTEGER, 1) AS num_installments,

        CASE WHEN payment_value ~ '^[0-9]+\.[0-9]{2}$' -- replace with NULL if not of correct price format
            THEN payment_value::NUMERIC(10,2)
            ELSE NULL
            END AS payment_value
    FROM deduplicate_payment_seq AS d
) AS processed_payments
WHERE payment_value IS NOT NULL
AND id in (SELECT order_id FROM final_orders); -- Make sure order id exists in orders table

-------------------------
-- Order reviews dataset
-------------------------

WITH deduplicate_reviews AS (
    SELECT DISTINCT ON (review_id, order_id)
        review_id,
        order_id,
        review_score,
        comment_title,
        comment_message,
        post_date,
        answer_date
    FROM staging_reviews
    WHERE review_id IS NOT NULL
    AND order_id IS NOT NULL
    AND review_score IS NOT NULL
    AND post_date IS NOT NULL
    ORDER BY review_id, order_id
)   
INSERT INTO final_reviews(
    review_id,
    order_id,
    review_score,
    comment_title,
    comment_message,
    post_date,
    answer_date
)
SELECT * FROM 
    (SELECT
        review_id::VARCHAR(50),
        order_id::VARCHAR(50),
        -- Cast only if the text is an integer 1-5
        CASE WHEN review_score ~ '^[1-5]$' THEN review_score::INTEGER
            ELSE NULL
            END AS review_score,
        -- Can be left NULL
        comment_title,
        comment_message,
        -- Cast only if date is in the correct format
        CASE WHEN post_date ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$' THEN post_date::TIMESTAMP::DATE
            ELSE NULL 
            END AS post_date,
        -- Can be left NULL
        CASE WHEN answer_date ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$' THEN answer_date::TIMESTAMP::DATE
            ELSE NULL
            END AS answer_date
        FROM deduplicate_reviews
    ) AS processed_reviews
WHERE review_score IS NOT NULL
AND post_date IS NOT NULL
AND order_id in (SELECT order_id FROM final_orders); -- Make sure order id exists in orders table

----------------
-- Error tables
----------------
DROP TABLE IF EXISTS rejected_orders CASCADE;
DROP TABLE IF EXISTS rejected_sellers CASCADE;
DROP TABLE IF EXISTS rejected_product_category CASCADE;
DROP TABLE IF EXISTS rejected_products CASCADE;
DROP TABLE IF EXISTS rejected_item_orders CASCADE;
DROP TABLE IF EXISTS rejected_customers CASCADE;
DROP TABLE IF EXISTS rejected_payments CASCADE;
DROP TABLE IF EXISTS rejected_reviews CASCADE;

-- rejected orders
CREATE TABLE rejected_orders AS (
    SELECT *, CASE 
                WHEN order_id IS NULL THEN 'NULL order_id'
                WHEN customer_id IS NULL THEN 'NULL customer_id'
                WHEN purchase_date IS NULL THEN 'NULL purchase_date' 
                WHEN purchase_date !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$' THEN 'Incorrect purchase_date format'
                END AS rejected_reason
    FROM staging_orders
    WHERE order_id IS NULL
    OR customer_id IS NULL
    OR purchase_date IS NULL
    OR purchase_date !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$'
);

-- rejected sellers
CREATE TABLE rejected_sellers AS (
    SELECT *, 'seller_id is NULL' as rejected_reason
    FROM staging_sellers
    WHERE seller_id IS NULL
);

-- rejected product categories
CREATE TABLE rejected_product_category AS (
    SELECT *, 'product_category is NULL' AS rejected_reason
    FROM staging_product_category
    WHERE product_category IS NULL
);

-- rejected products
CREATE TABLE rejected_products AS (
    SELECT *, CASE
                WHEN product_id IS NULL THEN 'NULL product_id'
                WHEN product_category_name IS NULL THEN 'NULL product_category_name'
                WHEN product_category_name NOT IN (SELECT product_category FROM final_product_category) THEN 'product_category_name not in parent'
                END AS rejected_reason
    FROM staging_products
    WHERE product_category_name NOT IN (SELECT product_category FROM final_product_category)
    OR product_id IS NULL
);

-- rejected item_orders
CREATE TABLE rejected_item_orders AS (
    SELECT *, CASE
                WHEN order_id IS NULL THEN 'NULL order_id'
                WHEN item_id IS NULL THEN 'NULL item_id'
                WHEN product_id IS NULL THEN 'NULL product_id'
                WHEN shipping_limit_date IS NULL THEN 'NULL shipping_date'
                WHEN seller_id IS NULL THEN 'NULL seller_id'
                WHEN shipping_limit_date !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$' THEN 'Incorrect shipping_limit_date format'
                WHEN price !~ '^[0-9]+\.[0-9]{2}$' THEN 'Incorrect price format'
                WHEN order_id NOT IN (SELECT order_id FROM final_orders) THEN 'order_id not in final_orders'
                WHEN seller_id NOT IN (SELECT seller_id FROM final_sellers) THEN 'seller_id not in final_sellers'
                WHEN product_id NOT IN (SELECT product_id FROM final_products) THEN 'product_id not in final_products'
                END AS rejected_reason
    FROM staging_item_orders
    WHERE order_id NOT IN (SELECT order_id FROM final_orders)
    OR seller_id NOT IN (SELECT seller_id FROM final_sellers)
    OR product_id NOT IN (SELECT product_id FROM final_products)
    OR order_id IS NULL
    OR item_id IS NULL
    OR product_id IS NULL
    OR shipping_limit_date IS NULL
    OR seller_id IS NULL
    OR shipping_limit_date !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$'
    OR price !~ '^[0-9]+\.[0-9]{2}$'
);

-- rejected customers
CREATE TABLE rejected_customers AS (
    SELECT *, CASE
                WHEN customer_id IS NULL THEN 'NULL customer_id'
                WHEN customer_unique_id IS NULL THEN 'NULL customer_unique_id'
                END AS rejected_reason
    FROM staging_customers
    WHERE customer_id NOT IN (SELECT customer_id FROM final_orders)
    OR customer_id IS NULL
    OR customer_unique_id IS NULL
);

-- rejected payments
CREATE TABLE rejected_payments AS (
    SELECT *, CASE
                WHEN order_id IS NULL THEN 'NULL order_id'
                WHEN payment_value !~ '^[0-9]+\.[0-9]{2}$' THEN 'Incorrect payment_value format'
                END AS rejected_reason
    FROM staging_payments
    WHERE order_id NOT IN (SELECT order_id FROM final_orders)
    OR order_id IS NULL
    OR payment_value IS NULL
    OR payment_value !~ '^[0-9]+\.[0-9]{2}$'
);

-- rejected reviews
CREATE TABLE rejected_reviews AS (
    SELECT *, CASE 
                WHEN review_id IS NULL THEN 'NULL review_id'
                WHEN order_id IS NULL THEN 'NULL order_id'
                WHEN review_score IS NULL THEN 'NULL review_score'
                WHEN post_date IS NULL THEN 'NULL post_date'
                WHEN review_score !~ '^[1-5]$' THEN 'Incorrect review_Score format'
                WHEN post_date !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$' THEN 'Incorrect post_date format'
                WHEN order_id NOT IN (SELECT order_id FROM final_orders) THEN 'order_id not in parent'
                END AS rejected_reason
    FROM staging_reviews
    WHERE order_id NOT IN (SELECT order_id FROM final_orders)
    OR review_id IS NULL
    OR order_id IS NULL
    OR review_score IS NULL
    OR post_date IS NULL
    OR review_score !~ '^[1-5]$'
    OR post_date !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$'
);

COMMIT;