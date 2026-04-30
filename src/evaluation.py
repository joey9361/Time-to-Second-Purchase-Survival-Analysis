from configuration.config import SEED_LIST
from model import RandomSurvivalForest
from sksurv.metrics import concordance_index_censored
import pandas as pd

def seed_evaluator(
    X_train,
    y_train,
    X_test,
    y_test,
    tuned_params: dict) -> pd.DataFrame:
    # Stabilized evaluation across multiple seeds
    seed_eval_rows = []

    for seed in SEED_LIST:
        seed_model = RandomSurvivalForest(**tuned_params, n_jobs=-1, random_state=seed)
        seed_model.fit(X_train, y_train)

        seed_test_pred = seed_model.predict(X_test)

        seed_test_c = concordance_index_censored(
            y_test['has_second_purchase'],
            y_test['days_until_second_purchase'],
            seed_test_pred
        )[0]

        seed_eval_rows.append({
            'seed': seed,
            'test_c_index': seed_test_c
        })
    seed_eval_df = pd.DataFrame(seed_eval_rows).sort(key=lambda x: x.get('test_c_index'), reverse=True)
    return seed_eval_df

# seed_eval_df = pd.DataFrame(seed_eval_rows)
# print(seed_eval_df)
# print("Test mean/std:", round(seed_eval_df['test_c_index'].mean(), 4), round(seed_eval_df['test_c_index'].std(), 4))
# print("Best test seed:", int(seed_eval_df.loc[seed_eval_df['test_c_index'].idxmax(), 'seed']))