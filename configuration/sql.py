# Query to load all features
OFFLINE_LOAD_FEATURES_SQL = "SELECT * FROM customer_first_purchase_features_purchase_time"

ONLINE_LOAD_FEATURES_SQL = "SELECT * FROM users_feature_engineering WHERE request_id = :request_id"

ONLINE_REJECTED_ROWS_SQL = '''
                        SELECT rejected_reason FROM rejected_user_orders WHERE request_id = :request_id 
                        UNION ALL 
                        SELECT rejected_reason FROM rejected_user_payments WHERE request_id = :request_id 
                        UNION ALL 
                        SELECT rejected_reason FROM rejected_user_order_items WHERE request_id = :request_id
                        '''

PRODUCT_CATEGORY_OPTIONS_SQL = 'SELECT product_category FROM feature_product_category_encoding'
PAYMENT_TYPE_OPTIONS_SQL = 'SELECT payment_type FROM feature_payment_type_encoding'
STATE_OPTIONS_SQL = 'SELECT seller_state FROM feature_seller_state_encoding'