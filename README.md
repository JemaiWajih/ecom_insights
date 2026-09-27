# E-Commerce Insights — Brazilian Olist Dataset

End-to-end e-commerce analysis covering customer retention, 
delivery performance, and review score trends.

## Project StructEcom_insights/
├── notebooks/
│ └── cohort_analysis.ipynb # Main analysis notebook
├── reports/
│ ├── cohort_heatmap.png # Retention heatmap
│ └── delivery_vs_review.png # Delivery time vs review score
├── sql/
│ └── star_schema.sql # Star schema design
├── utils/
│ └── helpers.py # Data loading utilities
├── requirements.txt
└── README.md

## Analysis Covers
- **Cohort Analysis** — Monthly customer retention tracking
- **Delivery Performance** — Average delivery days per state
- **Review Score Analysis** — Correlation between delivery time and satisfaction

## Dataset
Brazilian E-Commerce Public Dataset by Olist (via Kaggle)
- 99,441 orders | 2016–2018
- Download: https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce
- Place all CSVs in `data/raw/`

## Setup & Run
```bash
# Clone the repo
git clone https://github.com/JemaiWajih/ecom_insights.git
cd ecom_insights

# Create virtual environment
python -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Launch Jupyter
jupyter notebook
```

## Tools & Libraries
- Python 3.12
- Pandas — data manipulation
- Matplotlib — visualizations
- Jupyter Notebook — analysis environment

## Key Findings
- Customer retention drops significantly after month 1
- Northern states have the longest delivery times
- Strong negative correlation between delivery days and review scores

