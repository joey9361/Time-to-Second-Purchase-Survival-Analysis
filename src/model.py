from sksurv.ensemble import RandomSurvivalForest
import pandas as pd
import numpy as np
from sksurv.metrics import concordance_index_censored

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



