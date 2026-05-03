from pathlib import Path

import numpy as np
import pandas as pd

from src.database import Database

# Olist CSV headers -> columns in sql/00_schema/00_offline_staging.sql
_OLIST_STAGING_RENAMES: dict[str, dict[str, str]] = {
    "staging_customers": {
        "customer_zip_code_prefix": "zip_code",
        "customer_city": "city",
    },
    "staging_item_orders": {"order_item_id": "item_id"},
    "staging_payments": {"payment_installments": "num_installments"},
    "staging_reviews": {
        "review_comment_title": "comment_title",
        "review_comment_message": "comment_message",
        "review_creation_date": "post_date",
        "review_answer_timestamp": "answer_date",
    },
    "staging_orders": {
        "order_purchase_timestamp": "purchase_date",
        "order_approved_at": "order_approval_date",
        "order_delivered_carrier_date": "delivered_carrier_date",
        "order_delivered_customer_date": "delivered_customer_date",
        "order_estimated_delivery_date": "estimated_delivery_date",
    },
    "staging_product_category": {
        "product_category_name": "product_category",
        "product_category_name_english": "product_category_english",
    },
    "staging_products": {
        "product_name_lenght": "product_name_length",
        "product_description_lenght": "product_description_length",
    },
    "staging_sellers": {"seller_zip_code_prefix": "zip_code"},
}

# Target column order must match staging DDL (only these are inserted)
_STAGING_COLUMNS: dict[str, list[str]] = {
    "staging_customers": [
        "customer_id",
        "customer_unique_id",
        "zip_code",
        "city",
        "customer_state",
    ],
    "staging_item_orders": [
        "order_id",
        "item_id",
        "product_id",
        "seller_id",
        "shipping_limit_date",
        "price",
        "freight_value",
    ],
    "staging_payments": [
        "order_id",
        "payment_sequential",
        "payment_type",
        "num_installments",
        "payment_value",
    ],
    "staging_reviews": [
        "review_id",
        "order_id",
        "review_score",
        "comment_title",
        "comment_message",
        "post_date",
        "answer_date",
    ],
    "staging_orders": [
        "order_id",
        "customer_id",
        "order_status",
        "purchase_date",
        "order_approval_date",
        "delivered_carrier_date",
        "delivered_customer_date",
        "estimated_delivery_date",
    ],
    "staging_product_category": ["product_category", "product_category_english"],
    "staging_products": [
        "product_id",
        "product_category_name",
        "product_name_length",
        "product_description_length",
        "product_photos_qty",
        "product_weight_g",
        "product_length_cm",
        "product_height_cm",
        "product_width_cm",
    ],
    "staging_sellers": ["seller_id", "zip_code", "seller_city", "seller_state"],
}


def _align_raw_df_to_staging(table: str, df: pd.DataFrame) -> pd.DataFrame:
    renames = _OLIST_STAGING_RENAMES.get(table, {})
    df = df.rename(columns=renames)
    expected = _STAGING_COLUMNS[table]
    missing = [c for c in expected if c not in df.columns]
    if missing:
        raise ValueError(
            f"{table}: after Olist renames, still missing columns {missing}. "
            f"CSV columns: {list(df.columns)}"
        )
    out = df[expected].copy()
    for col in out.columns:
        out[col] = out[col].astype(str)
    return out


def create_staging_finals_tables(datamanager: Database, conn, *args):
        """Ensure staging/final tables exist (idempotent; no DROP per request)."""
        # execute staging sql file
        staging_sql = read_sql_file(args[0])
        datamanager.execute_script(staging_sql, conn=conn)
        # execute finals sql file
        finals_sql = read_sql_file(args[1])
        datamanager.execute_script(finals_sql, conn=conn)

def load_raw_staging_csvs(datamanager: Database, conn) -> None:
    """
    Load raw CSVs into offline staging tables.

    Replaces ``sql/02_load/02_load_raw_data.sql`` which uses ``\\COPY`` — that is a **psql**
    client command, not valid SQL for psycopg2/SQLAlchemy ``execute``.
    """
    root = Path(__file__).resolve().parent.parent
    loads: list[tuple[str, str]] = [
        ("staging_customers", "data/raw/customers_dataset.csv"),
        ("staging_item_orders", "data/raw/order_items_dataset.csv"),
        ("staging_payments", "data/raw/order_payments_dataset.csv"),
        ("staging_reviews", "data/raw/order_reviews_dataset.csv"),
        ("staging_orders", "data/raw/orders_dataset.csv"),
        ("staging_product_category", "data/raw/product_category_name_translation.csv"),
        ("staging_products", "data/raw/products_dataset.csv"),
        ("staging_sellers", "data/raw/sellers_dataset.csv"),
    ]
    for table, rel in loads:
        path = root / rel
        if not path.is_file():
            raise FileNotFoundError(f"Missing raw data file: {path}")
        df = pd.read_csv(path)
        df = _align_raw_df_to_staging(table, df)
        datamanager.pandas_to_sql(df, table, conn=conn)

def read_sql_file(sql_file_path: str) -> str:
    path = Path(sql_file_path)
    if not path.is_absolute():
        path = Path(__file__).resolve().parent.parent / path
    with open(path, encoding='utf-8') as file:
        return file.read()

def load_data(datamanager: Database):
    from configuration.config import STUDY_END_DATE, OFFLINE_LOAD_FEATURES_SQL
    # Main path: single load into memory (~90k rows; minibatch not required for this dataset)
    df = datamanager.load_query(OFFLINE_LOAD_FEATURES_SQL)
    # Convert cutoff date used for snapshot features (t_pred = purchase_date)
    df["t_pred_date"] = pd.to_datetime(df["t_pred_date"])
    # Target-censoring baseline uses t_pred_date so duration is measured after prediction time
    df["days_until_second_purchase"] = df["days_until_second_purchase"].fillna(
        (pd.Timestamp(STUDY_END_DATE) - df["t_pred_date"]).dt.days
    )
    
    return df

def split_data_stratified(df:pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    # Temporal sort baseline uses prediction cutoff timestamp (t_pred)
    df['t_pred_date'] = pd.to_datetime(df['t_pred_date'])
    df = df.sort_values(by='t_pred_date')

    # split dataframe into censored and uncensored rows
    censored_df = df[df['has_second_purchase'] == 0]
    uncensored_df = df[df['has_second_purchase'] == 1]
    # temp, test split ratios
    temp_censored_ratio = int(len(censored_df) * 0.8)
    temp_uncensored_ratio = int(len(uncensored_df) * 0.8)
    # temp, test splits for censored entries
    temp_censored = censored_df.iloc[:temp_censored_ratio]
    test_censored = censored_df.iloc[temp_censored_ratio:]
    # temp, test splits for uncensored entries
    temp_uncensored = uncensored_df.iloc[:temp_uncensored_ratio]
    test_uncensored = uncensored_df.iloc[temp_uncensored_ratio:]

    # merge censored and uncensored dataframe for test portion
    test_split = pd.concat([test_censored, test_uncensored])

    # train, validation split ratios
    train_censored_ratio = int(len(temp_censored) * (7/8))
    train_uncensored_ratio = int(len(temp_uncensored) * (7/8))
    # train, val split for censored entries
    train_censored = temp_censored.iloc[:train_censored_ratio]
    val_censored = temp_censored.iloc[train_censored_ratio:]
    # train, val split for uncensored entries
    train_uncensored = temp_uncensored.iloc[:train_uncensored_ratio]
    val_uncensored = temp_uncensored.iloc[train_uncensored_ratio:]
    # merge censored and uncensored dataframe for train, val portion
    train_split = pd.concat([train_censored, train_uncensored])
    val_split = pd.concat([val_censored, val_uncensored])
    return train_split, val_split, test_split

def create_target_array(train_split: pd.DataFrame, val_split: pd.DataFrame, test_split: pd.DataFrame) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    # create target component of form (event, duration)
    train_array_target = np.array(
        list(zip(train_split["has_second_purchase"], train_split["days_until_second_purchase"])),
        dtype=[("has_second_purchase", bool), ("days_until_second_purchase", np.float32)],
    )
    validate_array_target = np.array(
        list(zip(val_split["has_second_purchase"], val_split["days_until_second_purchase"])),
        dtype=[("has_second_purchase", bool), ("days_until_second_purchase", np.float32)],
    )
    test_array_target = np.array(
        list(zip(test_split["has_second_purchase"], test_split["days_until_second_purchase"])),
        dtype=[("has_second_purchase", bool), ("days_until_second_purchase", np.float32)],
    )
    return train_array_target, validate_array_target, test_array_target

