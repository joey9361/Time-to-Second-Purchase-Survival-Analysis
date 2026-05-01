from joblib import load
from src.database import create_database_manager
import pandas as pd
from configuration.config import SERVING_INPUT_TABLE_NAMES, ONLINE_REJECTED_ROWS_SQL


datamanager = create_database_manager()

class OnlineServing:
    def __init__(self, input_data: list[dict]):
        """Initialize a serving object with input data of each order submission to handle and make predictions"""
        self.input_data = input_data

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
            
    def _rejected_gate_check(self, path: str, request_id: str, conn):
        with open(path, 'r') as file:
            sql = file.read()
            rejected_gate_df = datamanager.load_query(sql, params={"request_id": request_id}, conn=conn)
            
            if not rejected_gate_df.iloc[0]['any_rejected_rows']:
                print('No rejected rows found for request_id: ', request_id)
            else:
                rejected_rows_df = datamanager.load_query(
                    sql = ONLINE_REJECTED_ROWS_SQL,
                    params={'request_id': request_id},
                    conn=conn)
                rejected_reason = rejected_rows_df['rejected_reason']
                for reason in rejected_reason:
                    print('Rejected reason: ', reason)
                    
                raise ValueError(f'Rejected rows found for request_id: {request_id}')

    def preprocess_user_input(self):
        """Insert staging rows and transform request_id rows into final tables."""
        request_id = self.input_data[0]["request_id"]

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
                datamanager.execute_script(sql, params={"request_id": request_id}, conn=conn)
            # check if any rows belonging to request_id exist in rejected tables, 
            # if so, prevent feature engineering from running
            self._rejected_gate_check(
                path='sql/maintenance/04_online_rejected_gate_check.sql', 
                request_id=request_id, 
                conn=conn)             
            # feature engineer within same transaction for atomicity
            with open('sql/03_transform/03_online_feature_eng.sql', 'r') as file:
                sql = file.read()
                datamanager.execute(sql, params={"request_id": request_id}, conn=conn)

    # def load_features(self):
    #     """Load features from users_feature_engineering table into the same format as the offline data sets"""
    #     datamanager.load_query(

    def make_predictions(self):
        """Take the row belonging to respective request_id in users_feature_engineering table and serve predictions"""
        
        pass

# periodic cleanup of old finished requests from online staging, finals, and feature engineering tables
def periodic_online_table_cleanup(retention_days: int = 14):
    """Delete rows from onlien staging, final, and feature engineering tables older than retention_days"""
    with datamanager.transaction() as conn:
        with open('sql/03_transform/03_online_cleanup.sql', 'r') as file:
            sql = file.read()
            datamanager.execute_script(sql, params= {'retention_days': retention_days}, conn=conn)
        print(f'Successfully cleaned up old requests from online staging, final, and feature engineering tables older than {retention_days} days')

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
    serving = OnlineServing(inputs)
    serving.preprocess_user_input()
   



    # df1 = user_input_to_pandas(final_user_orders)
    # df2 = user_input_to_pandas(final_user_order_items)
    # df3 = user_input_to_pandas(final_user_payments)

    # datamanager.pandas_to_sql(df1, "staging_user_orders")
    # datamanager.pandas_to_sql(df2, "staging_user_order_items")
    # datamanager.pandas_to_sql(df3, "staging_user_payments")
    print('gay')