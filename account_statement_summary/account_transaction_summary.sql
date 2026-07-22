/*
==============================================================================
  ACCOUNT TRANSACTION SUMMARY
  Detailed monthly account statement summary with running balances,
  turnover statistics, max/min balance dates, and average daily balance.
==============================================================================

  DESCRIPTION
  -----------
  Generates a consolidated monthly view of a customer account covering:
    - Maximum and minimum running balance with exact dates
    - Debit and credit counts, turnover, and average transaction size
    - Days the account closed in debit vs credit position
    - Average daily balance across the full month

  PARAMETERS
  ----------
  :ACCOUNT_NO   One or more account numbers
  :STARTDATE    Analysis start date  (DD-MON-YYYY e.g. 01-JAN-2025)
  :ENDDATE      Analysis end date    (DD-MON-YYYY e.g. 31-DEC-2025)

  DATABASE
  --------
  Oracle 19c — FCUBS core banking system via database link

  EXCLUDED TRANSACTION CODES
  --------------------------
  REVL, ATB, RVL — Revaluation and internal accounting entries excluded
  from balance calculations to reflect customer-facing balances only.

  AUTHOR
  ------
  Gbemileke Emmanuel Falade
  Senior Data Analyst, Advanced Analytics
  Union Bank of Nigeria Plc

==============================================================================
*/

WITH

-- 1. DATE SPINE
--    Generates a complete calendar date range between :STARTDATE and :ENDDATE.
--    Oracle has no native GENERATE_SERIES so we use recursive CTE to produce
--    one row per day. This guarantees every date appears in the output even
--    on days with no account transactions, which is critical for accurate
--    average daily balance calculation.
DateRange (DateValue) AS (
    SELECT CAST(:STARTDATE AS DATE) AS DateValue
    FROM   DUAL
    UNION ALL
    SELECT DateValue + 1
    FROM   DateRange
    WHERE  DateValue + 1 <= CAST(:ENDDATE AS DATE)
),

-- 2. RUNNING BALANCE PER TRANSACTION
--    Computes a cumulative running balance at each individual transaction
--    using a correlated subquery. Debits are negative, credits positive.
--    Currency-aware: NGN accounts use LCY_AMOUNT, foreign currency
--    accounts use FCY_AMOUNT.
running_sum AS (
    SELECT
        A.VALUE_DT                     AS TRANSACTION_DATE,
        A.AC_NO                        AS ACCOUNT_NO,
        A.AC_ENTRY_SR_NO               AS SERIALNOS,
        (
            SELECT NVL(SUM(
                DECODE(DRCR_IND,
                    'C',  DECODE(STRT.AC_CCY, 'NGN', STRT.LCY_AMOUNT, STRT.FCY_AMOUNT),
                          -DECODE(STRT.AC_CCY, 'NGN', STRT.LCY_AMOUNT, STRT.FCY_AMOUNT)
                )
            ), 0)
            FROM   FCUBS.ACVW_ALL_AC_ENTRIES STRT
            WHERE  STRT.AC_NO            IN (:ACCOUNT_NO)
            AND    STRT.AC_NO             = A.AC_NO
            AND    STRT.VALUE_DT         <= A.VALUE_DT
            AND    STRT.AC_ENTRY_SR_NO   <= A.AC_ENTRY_SR_NO
            AND    STRT.TRN_CODE     NOT IN ('REVL', 'ATB', 'RVL')
        ) AS RUNNING_SUM_OR_BALANCE
    FROM   FCUBS.ACVW_ALL_AC_ENTRIES A
    WHERE  A.AC_NO       IN (:ACCOUNT_NO)
    AND    A.TRN_CODE NOT IN ('REVL', 'ATB', 'RVL')
    AND    A.VALUE_DT BETWEEN :STARTDATE AND :ENDDATE
),

-- 3. DAILY CLOSING BALANCE
--    Extracts the last transaction of each day using ROW_NUMBER ordered
--    by serial number descending. The highest serial number on a given
--    date represents the day's closing position.
DailyClosingBalances AS (
    SELECT
        TRANSACTION_DATE,
        ACCOUNT_NO,
        RUNNING_SUM_OR_BALANCE,
        ROW_NUMBER() OVER (
            PARTITION BY ACCOUNT_NO, TRANSACTION_DATE
            ORDER BY SERIALNOS DESC
        ) AS RN
    FROM running_sum
),

FilteredDailyClosingBalances AS (
    SELECT
        TRANSACTION_DATE,
        ACCOUNT_NO,
        RUNNING_SUM_OR_BALANCE
    FROM DailyClosingBalances
    WHERE RN = 1
),

-- 4. ALL DATES SCAFFOLD
--    Joins the date spine to account numbers so every calendar date
--    has a row whether or not a transaction occurred that day.
AllDates AS (
    SELECT DateValue AS TRANSACTION_DATE
    FROM   DateRange
),

AccountDates AS (
    SELECT
        AD.TRANSACTION_DATE,
        COALESCE(FDCB.ACCOUNT_NO, :ACCOUNT_NO) AS ACCOUNT_NO,
        FDCB.RUNNING_SUM_OR_BALANCE
    FROM      AllDates AD
    LEFT JOIN FilteredDailyClosingBalances FDCB
           ON AD.TRANSACTION_DATE = FDCB.TRANSACTION_DATE
),

-- 5. FORWARD-FILL BALANCES ON DAYS WITH NO TRANSACTIONS
--    On days with no account activity the closing balance equals the
--    previous day's closing balance. This recursive CTE carries the last
--    known balance forward into NULL-balance rows so the average daily
--    balance calculation is accurate across the full calendar month.
RecursiveBalances (TRANSACTION_DATE, ACCOUNT_NO, RUNNING_SUM_OR_BALANCE) AS (
    SELECT TRANSACTION_DATE, ACCOUNT_NO, RUNNING_SUM_OR_BALANCE
    FROM   AccountDates
    WHERE  RUNNING_SUM_OR_BALANCE IS NOT NULL

    UNION ALL

    SELECT
        AD.TRANSACTION_DATE,
        AD.ACCOUNT_NO,
        COALESCE(AD.RUNNING_SUM_OR_BALANCE, RB.RUNNING_SUM_OR_BALANCE)
    FROM      AccountDates AD
    JOIN      RecursiveBalances RB
           ON AD.TRANSACTION_DATE = RB.TRANSACTION_DATE + 1
    WHERE  AD.RUNNING_SUM_OR_BALANCE IS NULL
),

-- 6. MONTHLY RUNNING BALANCES
--    Recomputes the running balance at every transaction point and joins
--    to account master for customer name. Used to identify exact dates
--    on which maximum and minimum balances occurred.
MonthlyBalances AS (
    SELECT
        TO_CHAR(A.TRN_DT, 'MONTH- YYYY')  AS PERIOD,
        A.TRN_DT                           AS TRANSACTION_DATE,
        A.AC_NO                            AS ACCOUNT_NO,
        B.AC_DESC                          AS NAME,
        A.AC_CCY,
        (
            SELECT NVL(SUM(
                DECODE(DRCR_IND,
                    'C',  DECODE(STRT.AC_CCY, 'NGN', STRT.LCY_AMOUNT, STRT.FCY_AMOUNT),
                          -DECODE(STRT.AC_CCY, 'NGN', STRT.LCY_AMOUNT, STRT.FCY_AMOUNT)
                )
            ), 0)
            FROM   FCUBS.ACVW_ALL_AC_ENTRIES STRT
            WHERE  STRT.AC_NO          = A.AC_NO
            AND    STRT.TRN_DT        <= A.TRN_DT
            AND    STRT.AC_ENTRY_SR_NO <= A.AC_ENTRY_SR_NO
            AND    STRT.TRN_CODE  NOT IN ('REVL', 'ATB', 'RVL')
        ) AS RUNNING_SUM_OR_BALANCE
    FROM       FCUBS.ACVW_ALL_AC_ENTRIES A
    INNER JOIN FCUBS.STTM_CUST_ACCOUNT B
            ON A.AC_NO = B.CUST_AC_NO
    WHERE  A.AC_NO      IN (:ACCOUNT_NO)
    AND    A.TRN_CODE NOT IN ('REVL', 'ATB', 'RVL')
    AND    A.TRN_DT BETWEEN :STARTDATE AND :ENDDATE
),

-- 7. MAX AND MIN BALANCES PER MONTH
MaxMinBalances AS (
    SELECT
        PERIOD,
        ACCOUNT_NO,
        NAME,
        AC_CCY,
        MAX(RUNNING_SUM_OR_BALANCE) AS MAX_RUNNING_SUM_OR_BALANCE,
        MIN(RUNNING_SUM_OR_BALANCE) AS MIN_RUNNING_SUM_OR_BALANCE
    FROM   MonthlyBalances
    GROUP  BY PERIOD, ACCOUNT_NO, NAME, AC_CCY
),

-- 8. DATES OF MAX AND MIN BALANCES
--    Uses KEEP DENSE_RANK to find the exact transaction date on which
--    the maximum and minimum balances were reached. Where multiple dates
--    share the same extreme balance the most recent date is returned.
MaxMinDates AS (
    SELECT
        M.PERIOD,
        M.ACCOUNT_NO,
        M.NAME,
        M.AC_CCY,
        M.MAX_RUNNING_SUM_OR_BALANCE,
        M.MIN_RUNNING_SUM_OR_BALANCE,
        MAX(MAX_BALANCES.TRANSACTION_DATE)
            KEEP (DENSE_RANK FIRST ORDER BY MAX_BALANCES.RUNNING_SUM_OR_BALANCE DESC)
            AS MAXIMUM_TRANSACTION_DATE,
        MAX(MIN_BALANCES.TRANSACTION_DATE)
            KEEP (DENSE_RANK FIRST ORDER BY MIN_BALANCES.RUNNING_SUM_OR_BALANCE ASC)
            AS MINIMUM_TRANSACTION_DATE
    FROM      MaxMinBalances M
    LEFT JOIN MonthlyBalances MAX_BALANCES
           ON M.PERIOD     = MAX_BALANCES.PERIOD
          AND M.ACCOUNT_NO = MAX_BALANCES.ACCOUNT_NO
          AND M.MAX_RUNNING_SUM_OR_BALANCE = MAX_BALANCES.RUNNING_SUM_OR_BALANCE
    LEFT JOIN MonthlyBalances MIN_BALANCES
           ON M.PERIOD     = MIN_BALANCES.PERIOD
          AND M.ACCOUNT_NO = MIN_BALANCES.ACCOUNT_NO
          AND M.MIN_RUNNING_SUM_OR_BALANCE = MIN_BALANCES.RUNNING_SUM_OR_BALANCE
    GROUP  BY M.PERIOD, M.ACCOUNT_NO, M.NAME, M.AC_CCY,
              M.MAX_RUNNING_SUM_OR_BALANCE, M.MIN_RUNNING_SUM_OR_BALANCE
),

-- 9. TRANSACTION SUMMARY (TURNOVER TABLE)
--    Aggregates monthly debit and credit counts, total turnover, and
--    average transaction size. Filtered to ITM_TYP = 'V' (value-dated).
TransactionSummary AS (
    SELECT
        acc                                                        AS ACCOUNT_NO,
        AC_DESC                                                    AS CUSTOMER_NAME,
        TO_CHAR(dt, 'MONTH- YYYY')                                AS PERIOD,
        SUM(dr_itm)                                               AS DEBIT_COUNT,
        SUM(dr_tur)                                               AS DEBIT_TURNOVER,
        ROUND((SUM(dr_tur) / NULLIF(SUM(dr_itm), 0)), 2)         AS DEBIT_AVG,
        SUM(cr_itm)                                               AS CREDIT_COUNT,
        SUM(cr_tur)                                               AS CREDIT_TURNOVER,
        ROUND((SUM(cr_tur) / NULLIF(SUM(cr_itm), 0)), 2)         AS CREDIT_AVG
    FROM       FCUBS.ICTB_ITM_TOV
    INNER JOIN FCUBS.STTM_CUST_ACCOUNT
            ON CUST_AC_NO = acc
    WHERE  acc    IN (:ACCOUNT_NO)
    AND    DT BETWEEN :STARTDATE AND :ENDDATE
    AND    ITM_TYP = 'V'
    GROUP  BY acc, TO_CHAR(dt, 'YYYY'), TO_CHAR(dt, 'MM'),
              TO_CHAR(dt, 'MONTH- YYYY'), AC_DESC
    ORDER  BY TO_CHAR(dt, 'YYYY') DESC, TO_CHAR(dt, 'MM') DESC
),

-- 10. CLOSING BALANCE COUNTS
--     Counts the number of days each month the account closed in a
--     debit (negative) vs credit (positive) balance using the
--     forward-filled RecursiveBalances so weekends are included.
ClosingBalanceCounts AS (
    SELECT
        TO_CHAR(TRANSACTION_DATE, 'MONTH- YYYY')                       AS PERIOD,
        ACCOUNT_NO,
        SUM(CASE WHEN RUNNING_SUM_OR_BALANCE <  0 THEN 1 ELSE 0 END)  AS DEBIT_CLOSING_BALANCE_COUNT,
        SUM(CASE WHEN RUNNING_SUM_OR_BALANCE >= 0 THEN 1 ELSE 0 END)  AS CREDIT_CLOSING_BALANCE_COUNT
    FROM   RecursiveBalances
    GROUP  BY TO_CHAR(TRANSACTION_DATE, 'MONTH- YYYY'), ACCOUNT_NO
),

-- 11. AVERAGE DAILY BALANCE
--     Mean closing balance across all calendar days in the month.
--     ADB = Sum of daily closing balances / Number of days in month.
--     Includes weekends and public holidays via forward-filled balance.
AverageBalances AS (
    SELECT
        TO_CHAR(TRANSACTION_DATE, 'MONTH- YYYY')                            AS PERIOD,
        ACCOUNT_NO,
        SUM(RUNNING_SUM_OR_BALANCE)                                         AS SUM_OF_DAILY_BALANCES,
        COUNT(TRANSACTION_DATE)                                             AS COUNT_OF_DAYS,
        ROUND(SUM(RUNNING_SUM_OR_BALANCE)
              / NULLIF(COUNT(TRANSACTION_DATE), 0), 2)                      AS AVERAGE_DAILY_BALANCE
    FROM   RecursiveBalances
    GROUP  BY TO_CHAR(TRANSACTION_DATE, 'MONTH- YYYY'), ACCOUNT_NO
)

-- FINAL OUTPUT
-- Joins all CTEs on ACCOUNT_NO and PERIOD to produce one row per
-- account per calendar month, ordered by balance date.
SELECT
    M.PERIOD,
    M.MAXIMUM_TRANSACTION_DATE          AS DATE_MAXIMUM_RUNNING_BALANCE,
    M.MINIMUM_TRANSACTION_DATE          AS DATE_MINIMUM_RUNNING_BALANCE,
    M.ACCOUNT_NO,
    M.NAME                              AS CUSTOMER_NAME,
    M.AC_CCY                            AS CCY,
    M.MAX_RUNNING_SUM_OR_BALANCE        AS MAXIMUM_RUNNING_BALANCE,
    M.MIN_RUNNING_SUM_OR_BALANCE        AS MINIMUM_RUNNING_BALANCE,
    T.DEBIT_COUNT,
    T.DEBIT_TURNOVER,
    T.DEBIT_AVG,
    T.CREDIT_COUNT,
    T.CREDIT_TURNOVER,
    T.CREDIT_AVG,
    C.DEBIT_CLOSING_BALANCE_COUNT,
    C.CREDIT_CLOSING_BALANCE_COUNT,
    AB.AVERAGE_DAILY_BALANCE
FROM      MaxMinDates M
LEFT JOIN TransactionSummary T
       ON M.ACCOUNT_NO = T.ACCOUNT_NO
      AND M.PERIOD     = T.PERIOD
LEFT JOIN ClosingBalanceCounts C
       ON M.ACCOUNT_NO = C.ACCOUNT_NO
      AND M.PERIOD     = C.PERIOD
LEFT JOIN AverageBalances AB
       ON M.ACCOUNT_NO = AB.ACCOUNT_NO
      AND M.PERIOD     = AB.PERIOD
ORDER BY M.MAXIMUM_TRANSACTION_DATE;
