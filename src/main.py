from preprocessing import load_data, split_data_stratified, create_target_array
from model import train_RSF_model, c_index_scorer
from tuning import permuter, drop_features_by_permutation, custom_stratified_cv, hyperparameter_tuning
from evaluation import seed_evaluator
from database import create_database_manager
from configuration.config import BASE_TRAIN_PARAMS, PERM_IMPORTANCE_THRESHOLD, STRATIFIED_CV_PARAMS, PARAM_GRID, GRID_SEARCH_PARAMS
from joblib import dump

datamanager = create_database_manager()

# 1) Data Preprocessing
# Load the data and drop untrainable features
df = load_data(datamanager)
# Split the data into train, validation, and test sets
train_split, val_split, test_split = split_data_stratified(df)
# Create target arrays for train, validation, and test sets
train_array_target, validate_array_target, test_array_target = create_target_array(train_split, val_split, test_split)

# 2) Model Training
# Train base model with all trainable features
base_model = train_RSF_model(train_split, train_array_target, BASE_TRAIN_PARAMS)
# Get base model c-index score
base_c_index = c_index_scorer(base_model, val_split, validate_array_target)
# 3) Feature Selection
# Get feature permutation importances
perm_importances = permuter(base_model, val_split, validate_array_target, base_c_index, **BASE_TRAIN_PARAMS)
# Drop features with importance lower than threshold
X_train_reduced, X_val_reduced, X_test_reduced = drop_features_by_permutation(perm_importances, PERM_IMPORTANCE_THRESHOLD, train_split, val_split, test_split)

# 4) Hyperparameter Tuning
cv_splits = custom_stratified_cv(X_train_reduced, train_array_target, STRATIFIED_CV_PARAMS)
grid_search = hyperparameter_tuning(
                X_train_reduced, 
                train_array_target, 
                PARAM_GRID, 
                scoring=c_index_scorer, 
                cv_splits=cv_splits, 
                grid_search_params=GRID_SEARCH_PARAMS
                )
tuned_model = grid_search.best_estimator_
test_c_index = c_index_scorer(tuned_model, test_split, test_array_target)

# 5) Model Evaluation
seed_evaluations = seed_evaluator(X_train_reduced, train_array_target, X_test_reduced, test_array_target, grid_search.best_params_)
average_test_c_index = seed_evaluations['test_c_index'].mean()
best_seed = seed_evaluations.iloc[0]['seed']

# 6) Save model and artifacts

dump()