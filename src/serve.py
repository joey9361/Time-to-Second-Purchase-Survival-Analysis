from joblib import load
from database import create_database_manager
import pandas as pd

datamanager = create_database_manager()

def user_input_to_pandas(user_input: dict) -> pd.DataFrame:
    """Convert raw user data inputs to a pandas df"""
    # some error handling here

    return pd.DataFrame(user_input, index=[0])
    
def preprocess_user_input(user_input: dict, table_name: str = 'staging_user_data'):
    user_input_series = user_input_to_pandas(user_input)
    datamanager.pandas_to_sql(user_input_series, table_name)

    datamanager.execute()
    


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

    df1 = user_input_to_pandas(final_user_orders)
    df2 = user_input_to_pandas(final_user_order_items)
    df3 = user_input_to_pandas(final_user_payments)

    datamanager.pandas_to_sql(df1, "staging_user_orders")
    datamanager.pandas_to_sql(df2, "staging_user_order_items")
    datamanager.pandas_to_sql(df3, "staging_user_payments")
    print('gay')