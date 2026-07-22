# customer-transaction-analytics
Oracle SQL, advanced CTEs, banking reporting

# Customer Transaction Analytics

![Oracle](https://img.shields.io/badge/Oracle-19c-red)
![SQL](https://img.shields.io/badge/Language-SQL-blue)
![License](https://img.shields.io/badge/License-MIT-green)

Production-grade Oracle SQL scripts built for Nigerian commercial
banking environments. Each script addresses a specific reporting
or analytical requirement using advanced CTE composition, recursive
queries, and Oracle window functions.

---

## Scripts

| Script | Description | Techniques |
|--------|-------------|------------|
| [account_transaction_summary](account_statement_summary/) | Monthly account statement with running balances, turnover, max/min dates, days in overdraft, and average daily balance | Recursive CTE, correlated subquery, KEEP DENSE_RANK, forward-fill |

---

## Database Environment

- **Database:** Oracle 19c
- **Core banking system:** Temenos FCUBS
- **Access pattern:** Read-only queries via database link
- **Schema:** FCUBS

---

## SQL Techniques Demonstrated

| Technique | Used in |
|-----------|---------|
| Recursive CTE (date spine generation) | account_transaction_summary |
| Correlated subquery for running totals | account_transaction_summary |
| ROW_NUMBER() window function | account_transaction_summary |
| KEEP DENSE_RANK for extreme-value dates | account_transaction_summary |
| Balance forward-fill via recursive CTE | account_transaction_summary |
| Multi-CTE pipeline composition | account_transaction_summary |
| Currency-aware amount selection | account_transaction_summary |
| NULLIF for safe division | account_transaction_summary |

---

## Usage

These scripts are designed to run in Oracle SQL Developer or
any Oracle-compatible SQL client connected to an FCUBS instance.
Replace bind parameters (`:ACCOUNT_NO`, `:STARTDATE`, `:ENDDATE`)
with actual values before executing.

Sample synthetic output is included in each script folder.

---

## Author

**Gbemileke Emmanuel Falade**
Senior Data Analyst and Data Scientist, Union Bank of Nigeria
Independent Data Consultant, Sapphire Virtual Networks Limited
MSc Data Science (Distinction), University of East London

GitHub: [github.com/gpfalade](https://github.com/gpfalade)
Published: The Punch Newspaper, Viewpoint Section, June 2026
