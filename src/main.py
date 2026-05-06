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
import json
from dotenv import load_dotenv
from joblib import dump
from src.database import Database

load_dotenv()
datamanager = create_database_manager()

def _json_safe(value):
    if hasattr(value, "item"):
        return value.item()
    if isinstance(value, dict):
        return {k: _json_safe(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [_json_safe(v) for v in value]
    return value

def save_model(model, model_filename: str):
    if not Path(PROJECT_ROOT / 'artifacts').exists():
        Path(PROJECT_ROOT / 'artifacts').mkdir(parents=True, exist_ok=True)

    model_path = PROJECT_ROOT / 'artifacts' / model_filename 
    dump(model, model_path)

def run_model_training(datamanager: Database, fast_mode: bool = False, run_feature_permutation: bool = True, run_hyperparameter_tuning: bool = True):
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

    if fast_mode:
        model_meta_path = PROJECT_ROOT / 'artifacts' / 'tuned_model_metadata.json'
        if not Path(model_meta_path).exists():
            raise FileNotFoundError(f"Model metadata file not found at {model_meta_path}, run hyperparameter tuning first.")
        with open(model_meta_path, 'r') as f:
            model_metadata = json.load(f)
        best_params = model_metadata.get('final_model_params', {})
        selected_features = model_metadata.get('selected_feature_columns', train_split.columns.tolist())
        train_reduced_split = train_split[selected_features]
        test_reduced_split = test_split[selected_features]

        pretuned_model = train_RSF_model(train_reduced_split, train_array_target, best_params)
        result_c_index = c_index_scorer(pretuned_model, test_reduced_split, test_array_target)
        save_model(pretuned_model, 'pretuned_model.joblib')
        return result_c_index

    # 2) Model Training
    # Train base model with all trainable features
    base_model = train_RSF_model(train_split, train_array_target, RSF_BASE_PARAMS)
    # Get base model c-index score
    base_c_index = c_index_scorer(base_model, val_split, validate_array_target)
    
    # 3) Feature Selection
    if run_feature_permutation:
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
    if run_hyperparameter_tuning:
        # Use reduced features if feature permutation was run
        X_train = X_train_reduced if run_feature_permutation else train_split
        X_test = X_test_reduced if run_feature_permutation else test_split
        # Create CV splits
        cv_splits = custom_stratified_cv(X_train, train_array_target, STRATIFIED_CV_PARAMS)
        grid_search = hyperparameter_tuning(
                        X_train, 
                        train_array_target, 
                        PARAM_GRID, 
                        scoring=c_index_scorer, 
                        cv_splits=cv_splits, 
                        grid_search_params=GRID_SEARCH_PARAMS
                        )
        tuned_model = grid_search.best_estimator_
        # Same columns as fit (permutation drop); raw test_split would mismatch feature_names_in_
        test_c_index = c_index_scorer(tuned_model, X_test, test_array_target)
        # 6) Save model and artifacts (path independent of cwd when run as python -m src.main)
        save_model(tuned_model, 'tuned_model.joblib')
        model_meta_path = PROJECT_ROOT / 'artifacts' / 'tuned_model_metadata.json'
        model_metadata = {
            "model_type": type(tuned_model).__name__,
            "best_params_from_grid_search": _json_safe(grid_search.best_params_),
            "final_model_params": _json_safe(tuned_model.get_params()),
            "selected_feature_columns": X_train.columns.tolist(),
            "num_selected_features": int(len(X_train.columns)),
            "test_c_index": float(test_c_index),
        }
        with open(model_meta_path, "w", encoding="utf-8") as f:
            json.dump(model_metadata, f, indent=2)
        print(f"successfully saved model to {PROJECT_ROOT / 'artifacts' / 'tuned_model.joblib'}")
        print(f"saved model metadata to {model_meta_path}")
        return test_c_index

    # 5) Save model and artifacts when no hyperparameter tuning was run
    if run_feature_permutation:
        permutated_untuned_model = train_RSF_model(X_train_reduced, train_array_target, RSF_BASE_PARAMS)
        save_model(permutated_untuned_model, 'permutated_untuned_model.joblib')
        return c_index_scorer(permutated_untuned_model, X_test_reduced, test_array_target)
    # if fully untuned base model 
    save_model(base_model, 'base_untuned_model.joblib')
    return c_index_scorer(base_model, test_split, test_array_target)


if __name__ == '__main__':
    datamanager = create_database_manager()
    test_c_index = run_model_training(datamanager)
    print(f'Test c-index: {test_c_index}')
