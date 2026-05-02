from sksurv.ensemble import RandomSurvivalForest
import pandas as pd
import numpy as np
from sksurv.metrics import concordance_index_censored
from joblib import load

def train_RSF_model(X_train:pd.DataFrame, y_train:np.ndarray, params:dict = None):
    model = RandomSurvivalForest(**params)
    model.fit(X_train, y_train)
    return model

def get_RSF_prediction(model:RandomSurvivalForest, X_test:pd.DataFrame):
    return model.predict(X_test)

# Custom scorer for GridSearchCV
def c_index_scorer(estimator, X, y):
    prediction = estimator.predict(X)
    return concordance_index_censored(y['has_second_purchase'], y['days_until_second_purchase'], prediction)[0]

def median_survival_days(step_fn) -> float | None:
    """First time t where S(t) <= 0.5; None if survival stays above 0.5 on the fitted grid."""
    t = np.asarray(step_fn.x, dtype=float)
    s = np.asarray(step_fn.y, dtype=float)
    mask = s <= 0.5
    if not np.any(mask):
        return None
    return float(t[np.argmax(mask)])

# Load the model
def load_model(model_path: str):
    """Load model from path"""
    model = load(model_path)
    return model

def restricted_mean_survival_days(step_fn) -> float:
    """Area under S(t) over the curve's time range (RMST on [t_min, t_max])."""
    t = np.asarray(step_fn.x, dtype=float)
    s = np.asarray(step_fn.y, dtype=float)
    if t.size < 2:
        return float(s[0]) * float(np.ptp(t)) if t.size else 0.0
    integrate = getattr(np, "trapezoid", np.trapz)
    return float(integrate(s, t))


def align_to_model(model: RandomSurvivalForest, X: pd.DataFrame) -> pd.DataFrame:
    """Reorder / pad columns to match training features."""
    names = getattr(model, "feature_names_in_", None)
    if names is None:
        return X.copy()
    return X.reindex(columns=list(names), fill_value=0).astype(np.float64, copy=False)

