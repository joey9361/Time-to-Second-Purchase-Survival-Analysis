# E-commerce customer survival (Olist)

An end-to-end machine learning pipeline built on PostgreSQL and Python, 
applying survival analysis to model customer return behaviour on the 
Brazilian Olist e-commerce dataset and serving predictions through FastAPI with a streamlit dashboard.
```

## Purpose

This project was built as a structured learning exercise to develop 
end-to-end data engineering and machine learning skills from scratch. 
The primary goal was not predictive performance but rather building 
a complete, production-aware pipeline — from raw relational data 
through feature engineering to a fitted survival model.
```

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
# Skills Demonstrated
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
```

Every bullet here is something concrete a hiring manager can ask you about in an interview. That is the point.

---



```markdown
## Results and Limitations


---

The fundamental challenge is predicting repeat purchase behaviour from 
a single transaction. With 94.5% of customers in the dataset making 
only one purchase, the available signal is inherently limited. Published 
research on similar single-transaction ecommerce prediction problems 
typically reports C-indices in the 0.58-0.68 range.

Features that would meaningfully improve performance — customer demographics, 
historical purchase frequency, external marketing data — are not present 
in this dataset. This is a known limitation of static Kaggle datasets 
versus production data environments.

The value of this project lies in the pipeline architecture and 
engineering decisions rather than the predictive outcome.
---

## Project structure

```
├── api.py                 # FastAPI app (lifespan loads model)
├── app.py                 # Streamlit UI
├── configuration/
│   ├── config.py          # SQL snippets, tuning grids, dropdown queries
│   └── path.py            # PROJECT_ROOT
├── data/raw/              # Olist CSVs (not in git if large—see Setup)
├── sql/
│   ├── 00_schema/         # Offline + online DDL
│   ├── 02_load/           # Legacy psql COPY script (optional reference)
│   ├── 03_transform/      # Offline + online transform & feature SQL
│   └── maintenance/       # Online cleanup, reset, rejected-row checks
├── src/
│   ├── main.py            # Train pipeline entrypoint
│   ├── preprocessing.py   # CSV → DB, sql file → string, offline feature load
│   ├── serve.py           # Online serving + periodic helpers
│   ├── model.py           # RSF training helpers + load_model
│   ├── database.py        # DB manager
│   ├── tuning.py
│   └── evaluation.py
├── artifacts/             # tuned_model.joblib (after training)
├── requirements.txt
└── README.MD
---

## Setup

1. **Python** 3.10+ recommended. Install deps:

   ```bash
   pip install -r requirements.txt
   pip install python-dotenv streamlit requests
   ```

   (`requirements.txt` lists the core stack; the UI and `.env` need the extra packages above.)

2. **PostgreSQL**: create a database and place **Olist-style CSVs** under `data/raw/` (see `configuration.config.TABLE_CSV_PATH_PAIRS` for expected filenames).

3. **Environment**: copy `.env` and set at least:

   - `DATABASENAME`, `DBUSER`, `DBPASSWORD`, `DBHOST`, `DBPORT`
   - `MODEL_PATH` (e.g. `artifacts/tuned_model.joblib`) for the API
   - For Streamlit: `FASTAPI_URL` if the API is not on `http://localhost:8000`

4. **Train** (builds tables, loads CSVs from disk, runs SQL transforms, saves the model):

   ```bash
   python -m src.main
   ```

5. **API**:

   ```bash
   python -m api
   ```

   or `uvicorn api:app --host 127.0.0.1 --port 8000` with the same env.

6. **Dashboard** (in another terminal):

   ```bash
   streamlit run app.py
   ```

**Be specific, not vague**
- Bad: "Built a database pipeline"
- Good: "Engineered 60+ features across 7 joined tables using window functions and CTEs in PostgreSQL"

**Be confident, not apologetic**
- Bad: "Unfortunately the model did not perform well due to data limitations"
- Good: "The C-index of 0.61 reflects the inherent signal ceiling of single-transaction prediction, consistent with published benchmarks"
# Reflection
What I've discovered during my time working on this project is that the most important thing before starting a project isn't what the code should look like, but rather, how your code and available data can address and solve a specific problem. At the start of this project, I did not define a specific problem well enough with proper consideration of the limitations of the dataset. It was only midway did I realize that having such an imbalanced dataset with very little uncensored cases did I truly feel the effects of this. I did not consider before starting that survival analysis can only truly be strong with rich temporal data which I had little of. This realization is what made me pivot my initial declared event as, **a customer never making another purchase** with the assumption that I would have a rich history of a customer having multiple purchases, to **a customer making a second purchase** based on first purchase information. This decision stemmed from not wanting a class imbalance of 
talk about data leakage issues and overoptimism of initial results

**Let process speak louder than results**
- Every section should answer the implicit question: "Does this person know what they are doing?" not "Did this project work?"

---

## Tone note

This README is meant to be accurate to **this** repo today (paths, FastAPI lifespan, Streamlit, env vars). Update the printed C-index and any metrics when you change splits or data.
