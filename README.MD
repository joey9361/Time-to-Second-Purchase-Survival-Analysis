# E-commerce customer survival (Olist)

A machine learning pipeline built on PostgreSQL and Python, 
applying survival analysis to model customer return behaviour on the 
Brazilian Olist e-commerce dataset and serving predictions through FastAPI with a streamlit dashboard.

## Purpose

This project was built as a structured learning exercise to develop 
end-to-end data engineering with SQL and machine learning skills from scratch. 
The primary learning goal was building a complete, production-aware pipeline from raw relational data 
through feature engineering to a fitted survival model; the model was still evaluated end-to-end on a held-out test set.

## Results at a glance

- **Task:** predict **time to a second purchase** from first-order information (survival analysis)
- **Model:** Random Survival Forest — 27 features after permutation-based selection, tuned via grid search
- **Test C-index:** 0.53 (see `artifacts/tuned_model_metadata.json` after a full training run)
- **Leakage control:** landmark time `t_pred` = first purchase date; features exclude post-landmark information
- **Split:** temporal ordering by `t_pred_date`, stratified on event vs censored
- **Serving:** FastAPI + Streamlit demo (train and predict paths share the same SQL feature definitions)

### Pipeline Overview

**Offline (training)**

```
CSV files (data/raw/) - 8 files
        │
        ▼
PostgreSQL staging / finals (schema + transform SQL)
        │
        ▼
Offline feature SQL → master feature table
        │
        ▼
Python: load features → stratified split → RSF + permutation drop + grid search
        │
        ▼
artifacts/tuned_model.joblib
```

**Online (serving)**

```
Streamlit form → POST /get_prediction (FastAPI)
        │
        ▼
Load model once (lifespan) from MODEL_PATH
        │
        ▼
Online staging/finals + transform + feature SQL (per request_id)
        │
        ▼
Risk score + survival summaries (median time, restricted mean)
```

SQL lives under `sql/` (numbered folders: schema, transform, maintenance). Python resolves paths from the repo root via `configuration/path.py` so runs do not depend on cwd.

---

## Skills Demonstrated
**PostgreSQL & Data Engineering**
- Designed and queried a normalised relational schema across 8 tables
- Built complex feature engineering pipelines using CTEs, window functions, aggregations
  and joins across orders/customers/items/payments/sellers/products/product_categories
- Diagnosed and resolved query performance issues using EXPLAIN ANALYZE, 
  materialised CTEs, and strategic indexing
- Implemented data leakage prevention via landmark time methodology
- Separate online validation/transform + feature scripts for request-scoped rows (same ideas, smaller scope).
- Maintenance scripts for cleanup / reset of online tables.

**Machine Learning & Python**
- Applied survival analysis methodology (Random Survival Forest) 
- Survival setup: event + time-to-event targets, censored rows handled in the training target structure.
- Built a modular Python pipeline, concordance index (C-index) as the main metric, permutation-based feature dropping, 
  then hyperparameter tuning via cross-validated grid search.
- Model serialized with **joblib** and loading joins relative `MODEL_PATH` to the project root.

**Software / API**
- Separation of concerns between data layer (PostgreSQL) and model layer (Python)
- Modular database manager class utilizing **SQLAlchemy** for reusable query execution, scripting, and transactions
- **FastAPI**: model loaded once at startup; prediction endpoint maps validation/DB errors to HTTP 422 where appropriate.
- **Streamlit** dashboard calling the API; blank form fields sent as JSON `null` for SQL.

---

## Results and Limitations

On the held-out test set, the tuned model achieves a **C-index of ~0.53**. That is below published ranges for similar single-transaction ecommerce problems (often ~0.58–0.68), which is expected given the data constraints below.

The fundamental challenge is predicting repeat purchase behaviour from 
a single transaction. With 94.5% of customers in the dataset making 
only one purchase, the available signal is inherently limited.

Features that would meaningfully improve performance: customer demographics, 
historical purchase frequency, external marketing data; are not present 
in this dataset. This is a known limitation of static Kaggle datasets 
versus production data environments.

The main value of this project is the pipeline architecture and engineering decisions (SQL feature layer, train/serve parity, leakage boundaries), with an honestly reported model metric rather than an overstated benchmark.

---

## Project structure

```text
├── api.py                 # FastAPI app (lifespan loads model)
├── app.py                 # Streamlit UI
├── configuration/
│   ├── config.py          # Hyperparameters, tuning grids, table/CSV mapping
│   ├── sql.py             # Shared SQL strings (offline load, online features)
│   └── path.py            # PROJECT_ROOT
├── data/raw/              # Olist CSVs (not in git if large—see Setup)
├── sql/
│   ├── 00_schema/         # Offline + online DDL
│   ├── 03_transform/      # Offline + online transform & feature SQL
│   └── maintenance/       # Online cleanup, reset, rejected-row checks
├── src/
│   ├── main.py            # Train pipeline entrypoint
│   ├── preprocessing.py   # CSV → DB, sql file → string, offline feature load
│   ├── serve.py           # Online serving + periodic helpers
│   ├── model.py           # RSF training helpers + load_model
│   ├── database.py        # DB manager
│   └── tuning.py
├── artifacts/             # tuned_model.joblib (after training)
│   └── tuned_model_metadata.json
├── requirements.txt
└── README.MD
```

---

## Setup (PowerShell / Windows)

1. **Python** 3.10+ recommended. From project root:

   ```powershell
   py -m venv .employee_churn_venv
   .\.employee_churn_venv\Scripts\Activate.ps1
   py -m pip install -r requirements.txt
   ```

2. **Data + PostgreSQL**: create a database, then download Olist CSVs from [Kaggle (Brazilian E-Commerce)](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) into `data/raw/`.

   - Create a Kaggle API token from your Kaggle account page (`kaggle.json`).
   - Put it at `%USERPROFILE%/.kaggle/kaggle.json`.
   - Install CLI (inside your venv):

   ```powershell
   py -m pip install kaggle
   ```

   - From project root:

   ```powershell
   kaggle datasets download -d olistbr/brazilian-ecommerce -p data/raw
   Expand-Archive -Path data/raw/brazilian-ecommerce.zip -DestinationPath data/raw -Force
   Remove-Item data/raw/brazilian-ecommerce.zip
   ```

   Expected filenames are listed in `configuration.config.TABLE_CSV_PATH_PAIRS`.

3. **Environment**: copy `.env.example` to `.env` and set your DB credentials and paths. At minimum:
   - `DATABASENAME`, `DBUSER`, `DBPASSWORD`, `DBHOST`, `DBPORT`
   - `MODEL_PATH=artifacts/tuned_model.joblib` (use `artifacts/pretuned_model.joblib` if you only ran `python -m src.main --fast`)
   - `FASTAPI_URL=http://localhost:8000` (for Streamlit)
   - `FASTAPI_HOST=127.0.0.1`, `FASTAPI_PORT=8000`

4. **Train model** (builds schema, loads CSVs, runs transforms, then fits the model):

   **Default (full pipeline)** — permutation feature drop, then grid search. Writes `artifacts/tuned_model.joblib` and `artifacts/tuned_model_metadata.json`. This is the run you want before serving or before using `--fast`.

   ```powershell
   python -m src.main
   ```

   **Fast retrain** — skips permutation and grid search. Requires `artifacts/tuned_model_metadata.json` from a previous full run (same data split logic still applies). Writes `artifacts/pretuned_model.joblib`. Point `MODEL_PATH` at that file if you serve this artifact (or run full training and keep `MODEL_PATH=artifacts/tuned_model.joblib`).

   ```powershell
   python -m src.main --fast
   ```

   **Full pipeline with pieces skipped** (only when you are *not* using `--fast`):

   ```powershell
   python -m src.main --no-permutation
   python -m src.main --no-tune
   python -m src.main --no-permutation --no-tune
   ```

   With `--fast`, any `--no-permutation` / `--no-tune` flags are ignored; fast mode already skips those stages.

5. **Run API** (new terminal, same venv):

   ```powershell
   python -m api
   ```

6. **Run Streamlit dashboard** (another terminal, same venv):

   ```powershell
   streamlit run app.py
   ```

   Submit a first-purchase scenario in the form to exercise the full online path: staging → transform → feature SQL → API prediction.

## Reflection

The biggest lesson from this project is that **the problem statement has to match what the data can actually support** before you worry about model choice or code structure.

I started without locking that down tightly enough. Partway through, the dataset constraints became obvious: almost everyone has only one observed purchase, so “uncensored” repeat-purchase events are rare and the usable temporal signal is thin. Survival methods work best when you have meaningful time-to-event variation and enough history; here, the ceiling is largely set by the data, not by tuning tricks.

That led to a deliberate pivot in the target:

- **Earlier idea:** model something like long-run “never purchasing again,” which implicitly assumed richer per-customer purchase history than this static extract really provides.
- **What I shipped instead:** predict **time to a second purchase** from first-purchase information, a problem that lines up with what the tables actually contain, and that avoids pushing an already extreme class imbalance into something even harder to learn.

Going forward I’m carrying the same habit: **define the outcome and leakage boundaries first**, sanity-check event rates and censoring, then commit to the pipeline.

