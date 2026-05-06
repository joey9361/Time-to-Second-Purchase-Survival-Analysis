# Study end date
STUDY_END_DATE = '2018-09-03'

# Columns to drop from features
DROP_COLS = [
"order_id", "customer_id", "order_status", "purchase_date",  
"t_pred_date", 'has_second_purchase', 'days_until_second_purchase', "customer_unique_id", "customer_zip", 
"latest_shipping_limit_date", "most_exp_product_id", "most_exp_prod_category", "most_freq_category", 
"val_seller_id", "val_seller_zip", "val_seller_city", "val_seller_state", 'total_order_value', 'request_id', 'ingested_at']

# Only keys accepted by sksurv RandomSurvivalForest.__init__ — used for **RSF_BASE_PARAMS
RSF_BASE_PARAMS = {
    'n_jobs': -1,
    'random_state': 13,
}
# Used by tuning.permuter (not an RSF hyperparameter)
PERMUTATION_N_REPETITIONS = 5

PERM_IMPORTANCE_THRESHOLD = -0.005
# Hyperparamater tuning grid
PARAM_GRID = {
    'n_estimators': [100, 200],
    'max_depth': [5, 10, 15],
    'min_samples_leaf': [50, 75, 100]
}

# Stratified CV parameters
STRATIFIED_CV_PARAMS = {
    'n_splits': 5, 
    'shuffle': True, 
    'random_state': 13
}

# Grid search parameters
GRID_SEARCH_PARAMS = {
    'n_jobs': -1,
    'error_score': 'raise'
}


SERVING_INPUT_TABLE_NAMES = ['staging_user_orders', 'staging_user_order_items', 'staging_user_payments']

# Olist CSV headers -> columns in sql/00_schema/00_offline_staging.sql
_OLIST_STAGING_RENAMES: dict[str, dict[str, str]] = {
    "staging_customers": {
        "customer_zip_code_prefix": "zip_code",
        "customer_city": "city",
    },
    "staging_item_orders": {"order_item_id": "item_id"},
    "staging_payments": {"payment_installments": "num_installments"},
    "staging_reviews": {
        "review_comment_title": "comment_title",
        "review_comment_message": "comment_message",
        "review_creation_date": "post_date",
        "review_answer_timestamp": "answer_date",
    },
    "staging_orders": {
        "order_purchase_timestamp": "purchase_date",
        "order_approved_at": "order_approval_date",
        "order_delivered_carrier_date": "delivered_carrier_date",
        "order_delivered_customer_date": "delivered_customer_date",
        "order_estimated_delivery_date": "estimated_delivery_date",
    },
    "staging_product_category": {
        "product_category_name": "product_category",
        "product_category_name_english": "product_category_english",
    },
    "staging_products": {
        "product_name_lenght": "product_name_length",
        "product_description_lenght": "product_description_length",
    },
    "staging_sellers": {"seller_zip_code_prefix": "zip_code"},
}

# Target column order must match staging DDL (only these are inserted)
_STAGING_COLUMNS: dict[str, list[str]] = {
    "staging_customers": [
        "customer_id",
        "customer_unique_id",
        "zip_code",
        "city",
        "customer_state",
    ],
    "staging_item_orders": [
        "order_id",
        "item_id",
        "product_id",
        "seller_id",
        "shipping_limit_date",
        "price",
        "freight_value",
    ],
    "staging_payments": [
        "order_id",
        "payment_sequential",
        "payment_type",
        "num_installments",
        "payment_value",
    ],
    "staging_reviews": [
        "review_id",
        "order_id",
        "review_score",
        "comment_title",
        "comment_message",
        "post_date",
        "answer_date",
    ],
    "staging_orders": [
        "order_id",
        "customer_id",
        "order_status",
        "purchase_date",
        "order_approval_date",
        "delivered_carrier_date",
        "delivered_customer_date",
        "estimated_delivery_date",
    ],
    "staging_product_category": ["product_category", "product_category_english"],
    "staging_products": [
        "product_id",
        "product_category_name",
        "product_name_length",
        "product_description_length",
        "product_photos_qty",
        "product_weight_g",
        "product_length_cm",
        "product_height_cm",
        "product_width_cm",
    ],
    "staging_sellers": ["seller_id", "zip_code", "seller_city", "seller_state"],
}

TABLE_CSV_PATH_PAIRS = [
        ("staging_customers", "data/raw/customers_dataset.csv"),
        ("staging_item_orders", "data/raw/order_items_dataset.csv"),
        ("staging_payments", "data/raw/order_payments_dataset.csv"),
        ("staging_reviews", "data/raw/order_reviews_dataset.csv"),
        ("staging_orders", "data/raw/orders_dataset.csv"),
        ("staging_product_category", "data/raw/product_category_name_translation.csv"),
        ("staging_products", "data/raw/products_dataset.csv"),
        ("staging_sellers", "data/raw/sellers_dataset.csv"),
    ]