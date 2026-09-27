"""
utils/helpers.py 
"""
import os
import pandas as pd


BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA__RAW = os.path.join(BASE_DIR, "data", "raw")


FILES = {
    "orders": "olist_orders_dataset.csv",
    "customers":"olist_customers_dataset.csv",
    "payments":"olist_order_payments_dataset.csv",
    "reviews":"olist_order_reviews_dataset.csv", 
}

# Loaders

def load(name: str, **kwargs) -> pd.DataFrame:
    path = os.path.join(DATA__RAW, FILES[name])
    if not os.path.exists(path):
        raise FileNotFoundError(
            f"\n[!] '{FILES[name]}' not found in data/raw/\n"
            f"     Download from: https:////www.kaggle.com/datasets/olistbr/brazilian-ecommerce\n"
            f" Then place all CSVs in: {DATA__RAW}"
        )
    df = pd.read_csv(path, **kwargs)
    print(f"[✓] Loaded {name:12s} -> {df.shape[0]:>7,} rows  {df.shape[1]:>2} cols")
    return df

def load_all() -> dict:
    """Load all core CSVs and return a dict of DataFrames."""
    return {name: load(name) for name in FILES}

# Quick EDA helpers

def explore(df: pd.DataFrame) -> str:
    mb = df.memory_usage(deep=True).sum() / 1024 ** 2
    return f"{mb:.2f} MB"

def parse_dates_inplace(df: pd.DataFrame, cols: list) -> pd.DataFrame:
    """Convert listed columns to datetime in place, coerce errors."""
    for col in cols:
        if col in df.columns:
            df[col] = pd.to_datetime(df[col], errors="coerce")
    return df
