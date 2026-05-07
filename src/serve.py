import logging
import pandas as pd
from src.database import create_database_manager
from configuration.config import SERVING_INPUT_TABLE_NAMES, DROP_COLS
from configuration.sql import (
    ONLINE_REJECTED_ROWS_SQL,
    ONLINE_LOAD_FEATURES_SQL,
    STATE_OPTIONS_SQL,
    PRODUCT_CATEGORY_OPTIONS_SQL,
    PAYMENT_TYPE_OPTIONS_SQL,
)
from sksurv.ensemble import RandomSurvivalForest
from src.model import align_to_model, median_survival_days, restricted_mean_survival_days
from src.preprocessing import create_staging_finals_tables, sql_to_string

_log = logging.getLogger(__name__)

datamanager = create_database_manager()

class RejectedInputError(Exception):
    """Raised when online transform leaves rows in rejected tables for this request."""

    def __init__(self, request_id: str, reasons: list[str]):
        """Initializes the RejectedInputError class."""
        self.request_id = request_id
        self.reasons = reasons
        super().__init__(f"Rejected rows for request_id={request_id}")


class OnlineServing:
    def __init__(self, input_data: list[list[dict]], model: RandomSurvivalForest):
        """Initialize a serving object with input data of each order submission to handle and make predictions"""
        self.input_data = input_data
        # input_data[0] is the order table: list of one dict per request
        self.request_id = input_data[0][0].get("request_id", '')
        self.features: pd.DataFrame = None
        self.model = model

    def new_input_data(self, input_data: list[dict]):
        """Modifies current self.input_data with new input data if previous input data got rejected during transformation"""
        self.input_data = input_data

        
    def _user_input_to_pandas(self) -> list[pd.DataFrame]:
        """Convert raw user data inputs to a pandas df"""
        input_dfs = []
        for chunk in self.input_data:
            input_dfs.append(pd.DataFrame(chunk))
        return input_dfs
            
    def _rejected_gate_check(self, path: str, conn):
        """
        Checks if any rows belonging to request_id exist in rejected tables, 
        if so, prevent feature engineering from running by raising a RejectedInputError
        """
        sql = sql_to_string(path)
        rejected_gate_df = datamanager.load_query(sql, params={"request_id": self.request_id}, conn=conn)
        
        if not rejected_gate_df.iloc[0]['any_rejected_rows']:
            _log.debug("No rejected rows for request_id=%s", self.request_id)
        else:
            rejected_rows_df = datamanager.load_query(
                sql = ONLINE_REJECTED_ROWS_SQL,
                params={'request_id': self.request_id},
                conn=conn)
            reasons = (
                rejected_rows_df['rejected_reason']
                .dropna()
                .astype(str)
                .tolist()
            )
            for reason in reasons:
                _log.warning("Rejected row reason (request_id=%s): %s", self.request_id, reason)
            raise RejectedInputError(self.request_id, reasons)

    def preprocess_user_input(self):
        """Insert staging rows and transform request_id rows into final tables."""

        # convert user input to pandas dfs
        user_input_dfs = self._user_input_to_pandas()

        with datamanager.transaction() as conn:
            table_paths = ('sql/00_schema/00_online_staging.sql', 'sql/00_schema/00_online_final.sql')
            create_staging_finals_tables(
                datamanager,
                conn,
                *table_paths
            )

            # insert dfs into own respective staging tables
            for i in range(len(user_input_dfs)):
                datamanager.pandas_to_sql(user_input_dfs[i], SERVING_INPUT_TABLE_NAMES[i], conn=conn)

            # run transformation queries and insert into own finals tables
            sql = sql_to_string('sql/03_transform/03_online_transform.sql')
            datamanager.execute_script(sql, params={"request_id": self.request_id}, conn=conn)
            # check if any rows belonging to request_id exist in rejected tables, 
            # if so, prevent feature engineering from running
            self._rejected_gate_check(
                path='sql/maintenance/04_online_rejected_gate_check.sql', 
                conn=conn)             
            # feature engineer within same transaction for atomicity
            sql = sql_to_string('sql/03_transform/03_online_feature_eng.sql')
            datamanager.execute(sql, params={"request_id": self.request_id}, conn=conn)

    def load_features_online(self):
        """Load features into df from users_feature_engineering table into the same format as the offline data sets"""
        df = datamanager.load_query(ONLINE_LOAD_FEATURES_SQL, params={"request_id": self.request_id})
        df["t_pred_date"] = pd.to_datetime(df["t_pred_date"]) 
        df = df.drop(DROP_COLS, axis=1, errors='ignore')
        self.features = df

    def make_predictions(self) -> dict:
        """Risk score plus simple time summaries from the predicted survival curve (days)."""
        if self.features is None or self.features.empty:
            raise ValueError("Features not loaded; call load_features_online() after preprocess_user_input() or " 
                                "resubmit the request.")

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
    """Deletes old rows from online staging/final/feature tables past retention_days."""
    with datamanager.transaction() as conn:
        sql = sql_to_string('sql/maintenance/04_online_table_cleanup_periodic.sql')
        datamanager.execute_script(sql, params= {'retention_days': retention_days}, conn=conn)
        _log.info(
            "Cleaned up online staging/final/feature rows older than %s days",
            retention_days,
        )

def reset_online_tables():
    """Reset online staging, final, and feature engineering tables"""
    with datamanager.transaction() as conn:
        sql = sql_to_string('sql/maintenance/04_online_table_reset.sql')
        datamanager.execute_script(sql, conn=conn)
        _log.info("Reset online staging, final, and feature engineering tables")

# acts as a factory
def create_online_serving(input_data: list[list[dict]], model: RandomSurvivalForest) -> dict:
    """
    Runs preprocess, loads features, returns the prediction dict for one request.

    This function does not load the .joblib file itself.

    Can raise for bad input / rejected rows etc.; the API turns those into HTTP errors.
    """
    serving = OnlineServing(input_data, model)
    serving.preprocess_user_input()
    serving.load_features_online()
    return serving.make_predictions()

def get_categorical_options():
    """Get all categorical options for the user to select from"""
    with datamanager.transaction() as conn:
        state_options = datamanager.load_query(STATE_OPTIONS_SQL, conn=conn)
        product_category_options = datamanager.load_query(PRODUCT_CATEGORY_OPTIONS_SQL, conn=conn)
        payment_type_options = datamanager.load_query(PAYMENT_TYPE_OPTIONS_SQL, conn=conn)
    return state_options, product_category_options, payment_type_options

