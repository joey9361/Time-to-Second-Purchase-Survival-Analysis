from src.preprocessing import (
    create_staging_finals_tables,
    create_target_array,
    load_features_offline,
    csv_to_staging_tables,
    sql_to_string,
    split_data_stratified,
)
from src.model import train_RSF_model, c_index_scorer
from src.tuning import permuter, drop_features_by_permutation, custom_stratified_cv, hyperparameter_tuning
from src.evaluation import seed_evaluator
from src.database import create_database_manager
from configuration.config import (
    GRID_SEARCH_PARAMS,
    PARAM_GRID,
    PERM_IMPORTANCE_THRESHOLD,
    PERMUTATION_N_REPETITIONS,
    RSF_BASE_PARAMS,
    STRATIFIED_CV_PARAMS,
    DROP_COLS
)
from configuration.path import PROJECT_ROOT
from pathlib import Path
from dotenv import load_dotenv
from joblib import dump
from src.database import Database

load_dotenv()
datamanager = create_database_manager()

def run_model_training(datamanager: Database):
    # 1) Data Preprocessing
    # create staging and final tables
    table_paths = ('sql/00_schema/00_offline_staging.sql', 'sql/00_schema/00_offline_finals.sql')
    with datamanager.transaction() as conn:
        create_staging_finals_tables(
            datamanager, 
            conn, 
            *table_paths)
        # Load csv into database
        csv_to_staging_tables(datamanager, conn)
        # Transform data
        transform_sql = sql_to_string('sql/03_transform/03_offline_transform.sql')
        datamanager.execute_script(transform_sql, conn=conn)
        # feature engineering
        feature_engineering_sql = sql_to_string('sql/03_transform/03_offline_feature_eng.sql')
        datamanager.execute_script(feature_engineering_sql, conn=conn)
    # Load the data and drop untrainable features
    df = load_features_offline(datamanager)
    # Split the data into train, validation, and test sets
    train_split, val_split, test_split = split_data_stratified(df)
    # Create target arrays for train, validation, and test sets
    train_array_target, validate_array_target, test_array_target = create_target_array(train_split, val_split, test_split)

    # Drop columns that are not trainable from each split
    train_split = train_split.drop(columns=DROP_COLS, errors="ignore")
    val_split = val_split.drop(columns=DROP_COLS, errors="ignore")
    test_split = test_split.drop(columns=DROP_COLS, errors="ignore")

    # 2) Model Training
    # Train base model with all trainable features
    base_model = train_RSF_model(train_split, train_array_target, RSF_BASE_PARAMS)
    # Get base model c-index score
    base_c_index = c_index_scorer(base_model, val_split, validate_array_target)
    # 3) Feature Selection
    # Get feature permutation importances
    perm_importances = permuter(
        base_model,
        val_split,
        validate_array_target,
        base_c_index,
        **RSF_BASE_PARAMS,
        n_repetitions=PERMUTATION_N_REPETITIONS,
    )
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
    # Same columns as fit (permutation drop); raw test_split would mismatch feature_names_in_
    test_c_index = c_index_scorer(tuned_model, X_test_reduced, test_array_target)

    # # 5) Model Evaluation
    # seed_evaluations = seed_evaluator(X_train_reduced, train_array_target, X_test_reduced, test_array_target, grid_search.best_params_)
    # average_test_c_index = seed_evaluations['test_c_index'].mean()
    # best_seed = seed_evaluations.iloc[0]['seed']

    # 6) Save model and artifacts (path independent of cwd when run as python -m src.main)
    if not Path(PROJECT_ROOT / 'artifacts').exists():
        Path(PROJECT_ROOT / 'artifacts').mkdir(parents=True, exist_ok=True)

    model_path = PROJECT_ROOT / 'artifacts' / 'tuned_model.joblib'
    dump(tuned_model, model_path)
    print(f"successfully saved model to {model_path}")
    return test_c_index

if __name__ == '__main__':
    datamanager = create_database_manager()
    test_c_index = run_model_training(datamanager)
    print(f'Test c-index: {test_c_index}')
