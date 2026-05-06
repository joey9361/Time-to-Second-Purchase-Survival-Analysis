from pathlib import Path

import numpy as np
import pandas as pd
from configuration.config import _OLIST_STAGING_RENAMES, _STAGING_COLUMNS, TABLE_CSV_PATH_PAIRS, STUDY_END_DATE
from configuration.sql import OFFLINE_LOAD_FEATURES_SQL
from configuration.path import PROJECT_ROOT
from src.database import Database

def _align_raw_df_to_staging(table: str, df: pd.DataFrame) -> pd.DataFrame:
    """Aligns the raw dataframe to the staging dataframe schema."""
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
        staging_sql = sql_to_string(args[0])
        datamanager.execute_script(staging_sql, conn=conn)
        # execute finals sql file
        finals_sql = sql_to_string(args[1])
        datamanager.execute_script(finals_sql, conn=conn)

def csv_to_staging_tables(datamanager: Database, conn) -> None:
    """
    Load raw CSVs into offline staging tables.
    """
    for table, rel in TABLE_CSV_PATH_PAIRS:
        path = PROJECT_ROOT / rel
        if not path.is_file():
            raise FileNotFoundError(f"Missing raw data file: {path}")
        df = pd.read_csv(path)
        df = _align_raw_df_to_staging(table, df)
        datamanager.pandas_to_sql(df, table, conn=conn)

def sql_to_string(sql_file_path: str) -> str:
    """Converts a SQL file to a string."""
    if Path(sql_file_path).is_absolute():
        path = Path(sql_file_path)
    else:
        path = PROJECT_ROOT / sql_file_path
    if not path.is_file():
        raise FileNotFoundError(f"Missing SQL file: {path}")
    with open(path, 'r', encoding='utf-8') as file:
        return file.read()

def load_features_offline(datamanager: Database):
    """Loads the features from the offline database."""
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
    """Splits the data into train, validation, and test sets using a stratified approach and ordered by prediction time."""
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
    """Creates the target array for the train, validation, and test sets."""
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

