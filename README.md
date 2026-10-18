# shopkart-sql-analysis
End-to-end MySQL analysis of an e-commerce business: sales trends, RFM segmentation, cohort retention, CAC/ROAS and more using window functions and CTEs.
# ShopKart: E-commerce SQL Analysis (MySQL)

End-to-end SQL analysis of an Indian online-retail business, **ShopKart**:
2 years of orders (Jan 2023 to Dec 2024), 900 customers, 48 products, 6 categories, 12 cities.
The goal is to answer the questions a business/data analyst gets asked every week
using only SQL.

> **Note on data:** the dataset is **synthetic**, created to behave like a real retailer:
> festive-season spikes, long-tail products, COD cancellations, slower delivery in some cities,
> and so on. It is not a real company's data.

## Repository structure

| File | What it does |
|------|--------------|
| `schema.sql` | Creates `shopkart_db` with 6 tables, keys, constraints and indexes |
| `data.sql` | ~7,000 rows of sample data |
| `analysis_queries.sql` | 40+ business questions with solutions, grouped in 9 sections (A to I) |

## Data model

```
customers ──< orders ──< order_items >── products
    │            │                          │
    └──< reviews >┴──────────────────────────┘
marketing_spend (monthly spend per acquisition channel)
```

## Metric definitions

- **Revenue** = `quantity * unit_price * (1 - discount%)` on **Delivered** orders only
- **Profit** = revenue - `quantity * cost_price`
- Customer-behaviour metrics (repeat rate, RFM, cohorts) use all non-cancelled orders
- All revenue queries run on a reusable view, `v_sales`

## What the analysis covers

| Section | Business questions | SQL used |
|---------|--------------------|----------|
| A. KPIs | Revenue, margin, AOV, order status mix | Aggregates, window `%` of total |
| B. Trends | MoM, YoY, quarterly, moving average, seasonality | `LAG`, running `SUM() OVER`, frames |
| C. Products | Category share, top-N per category, Pareto 80/20, discount impact | `ROW_NUMBER`, cumulative windows, `CASE` |
| D. Customers | Repeat rate, **RFM segmentation**, **cohort retention**, churn risk | `NTILE`, CTEs, `TIMESTAMPDIFF` |
| E. Geography | State/city revenue, favourite category per city | `RANK`, partitioned windows |
| F. Operations | Cancellation by payment type, return rate, delivery SLAs | Conditional aggregation |
| G. Marketing | CAC and ROAS by channel, spend vs revenue | Multi-CTE joins |
| H. Reviews | Rating by category, delivery speed vs rating | Joins, bucketing |
| I. Advanced | Market-basket (with **lift**), first-purchase LTV, spike orders, stored procedure | Self-joins, window filters, procedures |

## Key findings (from the queries in this repo)

1. **Growth:** revenue grew from ₹17.2 L (2023) to ₹58.6 L (2024), up **240%**; overall profit margin is **41.3%** and AOV ₹3,882.
2. **Seasonality:** Oct to Nov (festive season) delivers about **32.7%** of yearly revenue in both years, so inventory and ad budgets should peak by September.
3. **Concentration:** only **16 of 48 products** produce 80% of revenue (Pareto). Electronics, Home & Kitchen and Fashion make up about 85% of sales.
4. **Discounts don't buy volume:** lines with 21%+ discount earn a **26.4%** margin vs **47%** with no discount, yet units per order line are almost the same (1.21 vs 1.20).
5. **Customer value:** 43% of customers are repeat buyers. About 217 "Champions" (roughly a quarter of buyers) bring **64% of revenue**; 149 "At Risk" customers are worth a win-back campaign.
6. **Cash on Delivery risk:** COD orders are cancelled **13.3%** of the time vs **3.5%** for UPI.
7. **Delivery hurts ratings:** orders taking 5+ days average a **3.01** rating vs **3.89** for 1-2 days. Kochi is the worst city (5.0 days average, 71% of orders slow).
8. **Marketing efficiency:** Organic Search returns ₹11.9 per ₹1 spent (CAC ₹748) while Influencer returns only ₹1.2 (CAC ₹7,297), so shift budget away from Influencer.
9. **Basket analysis:** raw co-purchase counts are dominated by best sellers; using **lift** shows no strong product affinities (max lift about 2.5), so bundle offers should be tested, not assumed.

## How to run

Requires **MySQL 8.0+** (window functions and CTEs).

```bash
mysql -u root -p < schema.sql
mysql -u root -p < data.sql
mysql -u root -p < analysis_queries.sql
```

Or open the three files in MySQL Workbench and run them in that order.
Tested in strict `ONLY_FULL_GROUP_BY` mode.

## Skills demonstrated

`JOINs` · `CTEs` · `Window functions (RANK, NTILE, LAG, running totals)` ·
`Subqueries` · `Conditional aggregation` · `Views` · `Stored procedures` ·
`Cohort / RFM / Pareto / CAC-ROAS analysis` · `Translating SQL output into business recommendations`

## Author

Muskan, BTech CSE · aspiring Data Analyst
