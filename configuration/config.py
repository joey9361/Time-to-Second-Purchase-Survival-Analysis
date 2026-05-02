# Study end date
STUDY_END_DATE = '2018-09-03'

# Query to load all features
OFFLINE_LOAD_FEATURES_SQL = "SELECT * FROM customer_first_purchase_features_purchase_time"

# Columns to drop from features
DROP_COLS = [
"order_id", "customer_id", "order_status", "purchase_date",  
"t_pred_date", "has_second_purchase", "days_until_second_purchase", "customer_unique_id", "customer_zip", 
"latest_shipping_limit_date", "most_exp_product_id", "most_exp_prod_category", "most_freq_category", 
"val_seller_id", "val_seller_zip", "val_seller_city", "val_seller_state", 'total_order_value', 'request_id', 'ingested_at']

SEED_LIST = [13, 42, 67, 89, 123]

BASE_TRAIN_PARAMS = {
    'n_jobs': -1,
    'random_state': SEED_LIST[0],
    'n_repititions': 5
}

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
    'random_state': SEED_LIST[0]
}

# Grid search parameters
GRID_SEARCH_PARAMS = {
    'n_jobs': -1,
    'error_score': 'raise'
}
# Random Survival Forest parameters
RSF_PARAMS = {
    'n_estimators': 100, 
    'min_samples_leaf': 100, 
    'max_depth': 15,              
    'n_jobs': -1,       
    'random_state': 69
}

SERVING_INPUT_TABLE_NAMES = ['staging_user_orders', 'staging_user_order_items', 'staging_user_payments']

ONLINE_LOAD_FEATURES_SQL = "SELECT * FROM users_feature_engineering WHERE request_id = :request_id"

ONLINE_REJECTED_ROWS_SQL = '''
                        SELECT rejected_reason FROM rejected_user_orders WHERE request_id = :request_id 
                        UNION ALL 
                        SELECT rejected_reason FROM rejected_user_payments WHERE request_id = :request_id 
                        UNION ALL 
                        SELECT rejected_reason FROM rejected_user_order_items WHERE request_id = :request_id
                        '''

