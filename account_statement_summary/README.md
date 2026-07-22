# Account Transaction Summary

Monthly account statement summary with running balances, turnover
statistics, max/min balance dates, days in overdraft, and average
daily balance. Built for the FCUBS core banking system on Oracle 19c.

---

## Business Problem

Operations teams, relationship managers, and credit analysts need
a consolidated monthly view of a customer account that goes beyond
raw transaction lists. Specifically they need to know:

- What was the highest and lowest balance reached, and exactly when?
- How many transactions occurred and what was the total turnover?
- How many days did the account sit in a negative position?
- What was the true average daily balance including weekends?

This script produces all of that in a single query result, one row
per account per calendar month.

---

## Output Columns

| Column | Description |
|--------|-------------|
| PERIOD | Calendar month and year |
| DATE_MAXIMUM_RUNNING_BALANCE | Date the highest balance was reached |
| DATE_MINIMUM_RUNNING_BALANCE | Date the lowest balance was reached |
| ACCOUNT_NO | Account number |
| CUSTOMER_NAME | Account holder name |
| CCY | Account currency (NGN or foreign) |
| MAXIMUM_RUNNING_BALANCE | Highest intra-month running balance |
| MINIMUM_RUNNING_BALANCE | Lowest intra-month running balance |
| DEBIT_COUNT | Number of debit transactions |
| DEBIT_TURNOVER | Total debit value |
| DEBIT_AVG | Average debit transaction size |
| CREDIT_COUNT | Number of credit transactions |
| CREDIT_TURNOVER | Total credit value |
| CREDIT_AVG | Average credit transaction size |
| DEBIT_CLOSING_BALANCE_COUNT | Days account closed in negative balance |
| CREDIT_CLOSING_BALANCE_COUNT | Days account closed in positive balance |
| AVERAGE_DAILY_BALANCE | Mean daily closing balance across the month |

---

## Parameters

| Parameter | Format | Example |
|-----------|--------|---------|
| :ACCOUNT_NO | Account number string | '0123456789' |
| :STARTDATE | DD-MON-YYYY | '01-JAN-2025' |
| :ENDDATE | DD-MON-YYYY | '31-DEC-2025' |


---

## Technical Architecture

The script composes eleven CTEs in sequence. Each solves one
specific sub-problem and passes its result to the next.

```
DateRange → Complete date spine (recursive)
↓
running_sum → Running balance per transaction
↓
DailyClosingBalances → Last transaction of each day (ROW_NUMBER)
FilteredDailyClosingBalances → Closing balance only
↓
AccountDates → Every calendar date × account
↓
RecursiveBalances → Forward-fill on days with no transactions
↓
MonthlyBalances → Running balance at every transaction point
↓
MaxMinBalances → Monthly high and low balance
MaxMinDates → Exact dates of high and low (KEEP DENSE_RANK)
↓
TransactionSummary → Debit/credit counts and turnover
ClosingBalanceCounts → Days in debit vs credit position
AverageBalances → Mean daily closing balance
↓
FINAL SELECT → One row per account per month
```

---

## Key Technical Decisions

### Why a recursive CTE for the date spine?

Oracle SQL does not have a GENERATE_SERIES function like PostgreSQL.
The DateRange recursive CTE replicates this by adding one day on
each recursive pass until the end date is reached. Without a complete
date spine, days with no account activity would be missing from the
output and the average daily balance calculation would be overstated.

### Why KEEP DENSE_RANK for max/min dates?

Standard MAX() or MIN() cannot return the date associated with
the extreme value in the same aggregation step. KEEP DENSE_RANK
allows finding the date corresponding to the highest or lowest
balance within the same GROUP BY without a subquery join. Where
multiple dates share the same extreme balance, the most recent
date is returned.

### Why forward-fill with a recursive CTE?

On weekends and public holidays no transactions occur and the
FilteredDailyClosingBalances table has no row for those days.
The RecursiveBalances CTE carries the previous day's closing
balance forward into those gaps. This means DEBIT_CLOSING_BALANCE_COUNT
and AVERAGE_DAILY_BALANCE reflect every calendar day in the month,
not just transaction days. An account that sat in overdraft over
a weekend is correctly counted as two additional negative-balance days.

### Why exclude REVL, ATB, RVL?

These transaction codes represent internal revaluation and accounting
entries that adjust book positions but do not reflect actual customer
transactions. Including them would distort turnover figures and
produce running balances that do not match what the customer sees
on their statement.

### Currency handling

Nigerian Naira accounts use LCY_AMOUNT (local currency amount).
Foreign currency accounts use FCY_AMOUNT. The DECODE on AC_CCY
ensures the correct amount column is selected in both the running
balance and the turnover calculations.

---

## Sample Output

See [sample_output/sample_output.csv](sample_output/sample_output.csv)
for a synthetic example showing six months of output for one account.

---

## Database Environment

- **Database:** Oracle 19c
- **Core banking system:** Oracle FCUBS
- **Access:** Read-only
- **Schema:** FCUBS
- **Key tables:**
  - FCUBS.ACVW_ALL_AC_ENTRIES — All account entries view
  - FCUBS.STTM_CUST_ACCOUNT — Account master
  - FCUBS.ICTB_ITM_TOV — Transaction item turnover summary

---

## Compatibility

This script uses Oracle-specific syntax and will not run on
PostgreSQL, MySQL, or SQL Server without modification. Key
Oracle-specific features used:

- Recursive CTE with DUAL
- DECODE() function
- KEEP (DENSE_RANK FIRST ORDER BY ...)
- NVL() for null handling
