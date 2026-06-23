# Brazilian-e-Commerce-Data-Analysis-Reporting
Data Analysis pipeline on the Brazilian e-commerce Public Dataset by Olist (Kaggle) -- relational database design, SQL analysis (joins, aggregates, window functions, subqueries), Python-driven visualization.


## Objectives

- Designed a normalized relational schema for 9 related e-commerce CSV files
- Loading and Validation of the dataset in PostgreSQL.
- Apply SQL (window functions, CTEs, RFM segmentation)
- Visualize findings with Matplotlib/Seaborn

## Dataset

[Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) — ~100k orders placed between 2016-2018 across multiple Brazilian marketplaces, with order status, pricing, payment, freight, customer location, product attributes, and review-score data.

> The raw CSVs are **not** committed to this repo (see `.gitignore`) due to size and Kaggle's redistribution terms. Download them yourself — instructions below.

## Project Structure

```
olist-ecommerce-analysis/
├── README.md
├── requirements.txt
├── .gitignore
├── sql/
│   ├── 01_schema.sql              # CREATE TABLE statements, PK/FK, indexes
│   ├── 02_load_data.sql           # psql \copy import script
│   ├── 03_validation_queries.sql  # post-load data integrity checks
│   ├── 04_analysis_queries.sql    # 12 required business-question queries
│   └── 05_advanced_analysis.sql   # window functions, RFM, cohort analysis
├── src/
│   ├── config.py                  # env-based DB configuration
│   ├── db_connection.py           # SQLAlchemy engine + query helpers
│   ├── data_loader.py             # pandas-based CSV → Postgres loader
│   ├── run_analysis.py            # runs analysis queries, exports CSV
│   └── visualize.py                # generates all charts
├── data/
│   ├── raw/                       # put downloaded Kaggle CSVs here (gitignored)
│   └── processed/                 # query result CSVs (gitignored)
```

## Technologies Used

| Layer | Tool |
|---|---|
| Database | PostgreSQL 14+ |
| Language | Python 3.10+ |
| DB access | SQLAlchemy, psycopg2 |
| Data wrangling | pandas, NumPy |
| Visualization | Matplotlib, Seaborn |
| Version control | Git, GitHub |

## Installation

```bash
# 1. Clone the repository
git clone [INSERT GITHUB REPO URL HERE]
cd olist-ecommerce-analysis

# 2. Create a virtual environment
python -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate

# 3. Install dependencies
pip install -r requirements.txt
```

## Database Setup

```bash
# 1. Create the database (adjust user as needed)
createdb olist_db

# 2. Set environment variables (or create a .env file in the project root)
export OLIST_DB_HOST=localhost
export OLIST_DB_PORT=5432
export OLIST_DB_NAME=olist_db
export OLIST_DB_USER=postgres
export OLIST_DB_PASSWORD=userpasswd

# 3. Download the dataset from Kaggle and place all 9 CSVs in data/raw/
#    https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce

# 4. Create the schema and load the data — choose ONE method:

#    Method A: psql (pure SQL)
psql -d olist_db -f sql/01_schema.sql
psql -d olist_db -f sql/02_load_data.sql

#    Method B: Python (pandas-based)
python src/data_loader.py

# 5. Validate the import
psql -d olist_db -f sql/03_validation_queries.sql
```

## Running the Project

```bash
# Run the core analysis queries and export results to data/processed/
python src/run_analysis.py

# Generate all charts into outputs/charts/
python src/visualize.py

# Explore the advanced (window function / RFM) queries directly in psql
psql -d olist_db -f sql/05_advanced_analysis.sql
```

## License

This project is for academic purposes. The Olist dataset is subject to
its own [Kaggle license terms](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) — do not redistribute the raw CSVs.