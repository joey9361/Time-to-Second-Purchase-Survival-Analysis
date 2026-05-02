from database import Database
import pandas as pd
import numpy as np

def load_data(datamanager: Database):
    from configuration.config import STUDY_END_DATE, FEATURE_SQL, DROP_COLS
    # Main path: single load into memory (~90k rows; minibatch not required for this dataset)
    df = datamanager.load_query(FEATURE_SQL)
    # Convert cutoff date used for snapshot features (t_pred = purchase_date)
    df["t_pred_date"] = pd.to_datetime(df["t_pred_date"])
    # Target-censoring baseline uses t_pred_date so duration is measured after prediction time
    df["days_until_second_purchase"] = df["days_until_second_purchase"].fillna(
        (pd.Timestamp(STUDY_END_DATE) - df["t_pred_date"]).dt.days
    )
    # Drop columns that are not trainable
    df = df.drop(DROP_COLS, axis=1, errors='ignore')
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

