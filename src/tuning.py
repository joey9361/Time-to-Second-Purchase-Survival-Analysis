from typing import Iterable
from sklearn.base import BaseEstimator
from sksurv.metrics import concordance_index_censored
from sksurv.ensemble import RandomSurvivalForest
from sklearn.model_selection import StratifiedKFold, GridSearchCV
import pandas as pd
import numpy as np
from configuration.config import RSF_BASE_PARAMS

def permuter(
    model: RandomSurvivalForest, 
    X:pd.DataFrame, 
    Y:pd.DataFrame, 
    base_score:float, 
    **kwargs: dict # configuration parameters
    ) -> pd.Series:

    rng = np.random.RandomState(kwargs['random_state'])

    importance = {}

    for col in X.columns:
        running_c_index_avg = 0
        for _ in range(kwargs['n_repetitions']):
            X_perm = X.copy()
            X_perm[col] = rng.permutation(X_perm[col].values)

            perm_prediction = model.predict(X_perm)
            perm_c_index = concordance_index_censored(Y['has_second_purchase'], Y['days_until_second_purchase'], perm_prediction)[0]
            running_c_index_avg += perm_c_index

        importance[col] = base_score - (running_c_index_avg / kwargs['n_repetitions'])

    return pd.Series(importance).sort_values(ascending=False)

def drop_features_by_permutation(
    features:pd.Series, 
    importance_threshold:float, 
    X_train:pd.DataFrame, 
    X_validate:pd.DataFrame, 
    X_test:pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    """"""
    permuted_drop_cols = [col for col, val in features.items() if val < importance_threshold]
    X_train_reduced = X_train.drop(permuted_drop_cols, axis=1)
    X_val_reduced = X_validate.drop(permuted_drop_cols, axis=1)
    X_test_reduced = X_test.drop(permuted_drop_cols, axis=1)
    return X_train_reduced, X_val_reduced, X_test_reduced

def custom_stratified_cv(
    X_df: pd.DataFrame,
    y_array: np.ndarray,
    stratified_cv_params: dict) -> list[tuple[np.ndarray, np.ndarray]]:
    """"""
    cv_event_labels = y_array['has_second_purchase'].astype(int)
    strat_cv = StratifiedKFold(**stratified_cv_params)
    cv_splits = list(strat_cv.split(X_df, cv_event_labels))
    return cv_splits

def hyperparameter_tuning(
    X: pd.DataFrame,
    y: np.ndarray,
    param__tuning_grid: dict,
    estimator: BaseEstimator = RandomSurvivalForest(**RSF_BASE_PARAMS),
    scoring: str | callable = None,
    cv_splits: int | Iterable | None = None,
    grid_search_params: dict = None) -> GridSearchCV:
    """"""
    grid_search = GridSearchCV(
        estimator=estimator, 
        param_grid=param__tuning_grid, 
        scoring=scoring, cv=cv_splits, 
        **grid_search_params)
    grid_search.fit(X, y)
    return grid_search