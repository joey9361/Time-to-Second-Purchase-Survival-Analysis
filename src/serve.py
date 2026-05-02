from src.database import create_database_manager
import pandas as pd
from configuration.config import SERVING_INPUT_TABLE_NAMES, ONLINE_REJECTED_ROWS_SQL, ONLINE_LOAD_FEATURES_SQL, DROP_COLS
from sksurv.ensemble import RandomSurvivalForest
from src.model import align_to_model, load_model, median_survival_days, restricted_mean_survival_days
import os

datamanager = create_database_manager()

class OnlineServing:
    def __init__(self, input_data: list[dict], model: RandomSurvivalForest):
        """Initialize a serving object with input data of each order submission to handle and make predictions"""
        self.input_data = input_data
        self.request_id = input_data[0]["request_id"]
        self.features: pd.DataFrame = None
        self.model = model

    def new_input_data(self, input_data: list[dict]):
        """Modifies current self.input_data with new input data if previous input data got rejected during transformation"""
        self.input_data = input_data

        
    def _user_input_to_pandas(self) -> list[pd.DataFrame]:
        """Convert raw user data inputs to a pandas df"""
        # some error handling here
        input_dfs = []
        for input in self.input_data:
            df = pd.DataFrame(input, index=[0])
            input_dfs.append(df)
        return input_dfs

    def _ensure_online_tables(self, conn):
        """Ensure staging/final tables exist (idempotent; no DROP per request)."""
        with open('sql/00_schema/00_online_staging.sql', 'r') as file:
            sql = file.read()
            datamanager.execute_script(sql, conn=conn)
        with open('sql/00_schema/00_online_final.sql', 'r') as file:
            sql = file.read()
            datamanager.execute_script(sql, conn=conn)
            
    def _rejected_gate_check(self, path: str, conn):
        with open(path, 'r') as file:
            sql = file.read()
            rejected_gate_df = datamanager.load_query(sql, params={"request_id": self.request_id}, conn=conn)
            
            if not rejected_gate_df.iloc[0]['any_rejected_rows']:
                print('No rejected rows found for request_id: ', self.request_id)
            else:
                rejected_rows_df = datamanager.load_query(
                    sql = ONLINE_REJECTED_ROWS_SQL,
                    params={'request_id': self.request_id},
                    conn=conn)
                rejected_reason = rejected_rows_df['rejected_reason']
                for reason in rejected_reason:
                    print('Rejected reason: ', reason)
                    
                raise ValueError(f'Rejected rows found for request_id: {self.request_id}')

    def preprocess_user_input(self):
        """Insert staging rows and transform request_id rows into final tables."""

        # convert user input to pandas dfs
        user_input_dfs = self._user_input_to_pandas()

        with datamanager.transaction() as conn:
            self._ensure_online_tables(conn)

            # insert dfs into own respective staging tables
            for i in range(len(user_input_dfs)):
                datamanager.pandas_to_sql(user_input_dfs[i], SERVING_INPUT_TABLE_NAMES[i], conn=conn)

            # run transformation queries and insert into own finals tables
            with open('sql/03_transform/03_online_transform.sql', 'r') as file:
                sql = file.read()
                datamanager.execute_script(sql, params={"request_id": self.request_id}, conn=conn)
            # check if any rows belonging to request_id exist in rejected tables, 
            # if so, prevent feature engineering from running
            self._rejected_gate_check(
                path='sql/maintenance/04_online_rejected_gate_check.sql', 
                conn=conn)             
            # feature engineer within same transaction for atomicity
            with open('sql/03_transform/03_online_feature_eng.sql', 'r') as file:
                sql = file.read()
                datamanager.execute(sql, params={"request_id": self.request_id}, conn=conn)

    def load_features(self):
        """Load features into df from users_feature_engineering table into the same format as the offline data sets"""
        df = datamanager.load_query(ONLINE_LOAD_FEATURES_SQL, params={"request_id": self.request_id})
        df["t_pred_date"] = pd.to_datetime(df["t_pred_date"]) 
        df = df.drop(DROP_COLS, axis=1, errors='ignore')
        self.features = df

    def make_predictions(self) -> dict:
        """Risk score plus simple time summaries from the predicted survival curve (days)."""
        if self.features is None or self.features.empty:
            raise ValueError("Features not loaded; call load_features() after preprocess_user_input().")

        X = align_to_model(self.model, self.features)
        risk = float(self.model.predict(X)[0])
        step_fn = self.model.predict_survival_function(X, return_array=False)[0]
        median_days = median_survival_days(step_fn)
        mean_survival_days = restricted_mean_survival_days(step_fn)

        out = {
            "request_id": self.request_id,
            "risk_score": risk,
            "median_days_until_second_purchase": median_days,
            "restricted_mean_survival_days": mean_survival_days,
            "note": (
                "median_days is the first time on the curve where S(t)<=0.5 (None if never crossed). "
                "restricted_mean_survival_days is the area under S(t) over the curve support (interpretable expected horizon)."
            ),
        }
        self.last_prediction = out
        return out

# periodic cleanup of old finished requests from online staging, finals, and feature engineering tables
def periodic_online_table_cleanup(retention_days: int = 14):
    """Delete rows from onlien staging, final, and feature engineering tables older than retention_days"""
    with datamanager.transaction() as conn:
        with open('sql/03_transform/03_online_cleanup.sql', 'r') as file:
            sql = file.read()
            datamanager.execute_script(sql, params= {'retention_days': retention_days}, conn=conn)
        print(f'Successfully cleaned up old requests from online staging, final, and feature engineering tables older than {retention_days} days')

# acts as a factory
def create_online_serving(input_data: list[dict]) -> dict:
    """Manage the serving layer"""
    # call load model
    model = load_model(os.getenv("MODEL_PATH"))
    # instantiate OnlineServing and inject the model and input data
    serving = OnlineServing(input_data, model)
    # On failure, rollback the transaction and raise an error
    while True:
        try:
            serving.preprocess_user_input()
            break
        except ValueError as e:
            new_input_data = None # Call API to get new input data
            serving.new_input_data(new_input_data)
            continue
            raise e
    # Get new input data and call new_input_data
    # call load_features
    serving.load_features()
    # call make_predictions
    return serving.make_predictions()

if __name__ == "__main__":
    final_user_orders = {
        "request_id": "req_000001",
        "order_id": "order_000001",
        "customer_id": "cust_000001",
        "customer_unique_id": "custuniq_000001",
        "customer_zip": 13083,
        "customer_city": "campinas",
        "customer_state": "SP",
        "order_status": "delivered",
        "purchase_date": "2018-08-15"
    }

    final_user_order_items = {
            "request_id": "req_000001",
            "order_id": "order_000001",
            "item_id": 1,
            "product_id": "prod_000101",
            "seller_id": "seller_000501",
            "shipping_limit_date": "2018-08-20",
            "price": 129.90,
            "freight_value": 18.50,
            "product_category_name": "cama_mesa_banho",
            "seller_zip": 22041,
            "seller_city": "rio de janeiro",
            "seller_state": "RJ"
        }
        
    final_user_payments = {
            "request_id": "req_000001",
            "order_id": "order_000001",
            "payment_sequential": 1,
            "payment_type": "credit_card",
            "num_installments": 3,
            "payment_value": 148.40
        }

    inputs = [final_user_orders, final_user_order_items, final_user_payments]
    model = load_model("artifacts/tuned_model.joblib")
    serving = OnlineServing(inputs, model)
    serving.preprocess_user_input()
    serving.load_features()
    print(serving.make_predictions())

    # df1 = user_input_to_pandas(final_user_orders)
    # df2 = user_input_to_pandas(final_user_order_items)
    # df3 = user_input_to_pandas(final_user_payments)

    # datamanager.pandas_to_sql(df1, "staging_user_orders")
    # datamanager.pandas_to_sql(df2, "staging_user_order_items")
    # datamanager.pandas_to_sql(df3, "staging_user_payments")
    print('gay')