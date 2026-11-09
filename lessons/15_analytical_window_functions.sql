-- Lesson 15: Analytical Window Functions for Data Science
-- English reference notes. All statements are read-only and self-contained.
-- Execute one complete SELECT or WITH ... SELECT statement at a time.
-- VALUES creates query-local sample data, not permanent tables.
-- A CTE exists only within its statement; definitions are repeated below.
-- Daily examples contain one row per date; channel examples contain one row
-- per channel per date. Dates are consecutive within each sample partition.
-- Assume complete revenue data: zero means known zero revenue, not missing data.


-- 01. Running total: sum from the partition's first row through the current row.
-- A window calculation preserves individual rows; ordinary GROUP BY aggregates
-- them into summary rows. OVER defines the window for each output row.
-- ORDER BY inside OVER controls calculation order, not final display order.
-- Without PARTITION BY, all input rows belong to one partition.
-- ROWS BETWEEN ... AND ... specifies a frame using row positions.
-- UNBOUNDED PRECEDING: the first row of the current partition.
-- CURRENT ROW: the row being calculated, not the current calendar date.

WITH daily_revenue (paid_date, revenue) AS (
    VALUES
        (DATE '2026-11-01', 100.00),
        (DATE '2026-11-02',   0.00),
        (DATE '2026-11-03',  50.00)
)
SELECT
    paid_date,
    revenue,
    SUM(revenue) OVER (
        ORDER BY paid_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_revenue
FROM daily_revenue
ORDER BY paid_date;

-- Expected cumulative values: 100, 100, 150.
-- The start stays at the first row while the end advances with the current row.


-- 02. Moving window: the previous row plus the current row.
-- 1 PRECEDING means one row before the current row, not one calendar day ago.
-- Here consecutive dates and one row per date make two rows equal two days.
-- SUM calculates the window total; AVG calculates its average.

WITH daily_revenue (paid_date, revenue) AS (
    VALUES
        (DATE '2026-11-01', 100.00),
        (DATE '2026-11-02',   0.00),
        (DATE '2026-11-03',  50.00)
)
SELECT
    paid_date,
    revenue,
    SUM(revenue) OVER (
        ORDER BY paid_date
        ROWS BETWEEN 1 PRECEDING AND CURRENT ROW
    ) AS two_day_revenue,
    AVG(revenue) OVER (
        ORDER BY paid_date
        ROWS BETWEEN 1 PRECEDING AND CURRENT ROW
    ) AS two_day_average_revenue
FROM daily_revenue
ORDER BY paid_date;

-- Expected two-day totals: 100, 100, 50; two-day averages: 100, 50, 25.
-- On November 3, the frame contains 0 and 50, excluding November 1's 100.


-- 03. A three-row moving average needs two preceding rows plus the current row.
-- CURRENT ROW already contributes one row: N rows requires N - 1 PRECEDING.
-- At the beginning, use the available rows: these are partial windows.
-- AVG divides by the number of non-NULL values present, not a fixed three.
-- Zero counts as a value; NULL does not contribute to AVG's denominator.

WITH daily_revenue (paid_date, revenue) AS (
    VALUES
        (DATE '2026-11-01', 100.00),
        (DATE '2026-11-02',   0.00),
        (DATE '2026-11-03',  50.00)
)
SELECT
    paid_date,
    revenue,
    AVG(revenue) OVER (
        ORDER BY paid_date
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS three_day_average_revenue
FROM daily_revenue
ORDER BY paid_date;

-- Expected: 100 / 1 = 100; (100 + 0) / 2 = 50; (100 + 0 + 50) / 3 = 50.
-- With date gaps, ROWS still counts rows, not elapsed days. Build a complete
-- date spine first when the business definition requires every calendar date.


-- 04. LAG retrieves the preceding row's value within the same partition.
-- LAG(revenue) defaults to an offset of one row and a fallback of NULL.
-- LAG uses row offsets, not the aggregate window frame; no ROWS clause is needed.
-- The first row has no predecessor, so its previous revenue is NULL, not zero.

WITH daily_revenue (paid_date, revenue) AS (
    VALUES
        (DATE '2026-11-01', 100.00),
        (DATE '2026-11-02',   0.00),
        (DATE '2026-11-03',  50.00)
)
SELECT
    paid_date,
    revenue,
    LAG(revenue) OVER (ORDER BY paid_date) AS previous_day_revenue
FROM daily_revenue
ORDER BY paid_date;

-- Expected previous values: NULL, 100, 0.
-- LAG does not automatically find yesterday. With missing dates, the previous
-- row may be several days earlier. The previous_day alias relies on daily continuity.


-- 05. NULLIF protects division from a zero denominator.
-- NULLIF(a, b): return NULL if a equals b; otherwise return the first value, a.
-- Numeric division by NULL returns NULL; division by zero raises an error.
-- A blank result cell in these examples represents NULL, not numeric zero.

SELECT
    NULLIF(0, 0) AS zero_denominator,
    NULLIF(100, 0) AS nonzero_denominator,
    50.00 / NULL::numeric AS division_by_null,
    50.00 / NULLIF(0, 0) AS protected_division;

-- Expected: NULL, 100, NULL, NULL. None of these expressions divides by zero.
-- NULLIF is not COALESCE: it can remove a sentinel zero rather than fill a NULL.


-- 06. Revenue change and percentage growth are different measures.
-- change = current - previous
-- growth_pct = 100 * (current - previous) / previous
-- First calculate LAG in a CTE; then reuse its output alias in the outer SELECT.
-- An alias introduced in one SELECT expression is not available to another
-- expression in that same SELECT list. A CTE makes the calculation stages clear.
-- Use decimal arithmetic to avoid integer division if source measures are integers.

WITH daily_revenue (paid_date, revenue) AS (
    VALUES
        (DATE '2026-11-01', 100.00),
        (DATE '2026-11-02',   0.00),
        (DATE '2026-11-03',  50.00),
        (DATE '2026-11-04', 100.00)
),
revenue_with_previous AS (
    SELECT
        paid_date,
        revenue,
        LAG(revenue) OVER (ORDER BY paid_date) AS previous_day_revenue
    FROM daily_revenue
)
SELECT
    paid_date,
    revenue,
    previous_day_revenue,
    revenue - previous_day_revenue AS revenue_change,
    100.0 * (revenue - previous_day_revenue)
        / NULLIF(previous_day_revenue, 0) AS revenue_growth_pct
FROM revenue_with_previous
ORDER BY paid_date;

-- Expected (date, previous revenue, change, growth_pct):
-- November 1: NULL, NULL, NULL -- no previous observation.
-- November 2: 100, -100, -100 -- revenue fell from 100 to 0: a 100% decrease.
-- November 3:   0,   50, NULL -- ordinary percentage growth from zero is undefined.
-- November 4:  50,   50,  100 -- revenue doubled from 50 to 100: 100% growth.
-- A result of 100 in the pct column means 100%, not 1%.
-- Reaching 200% of the previous value means growing BY 100%, not BY 200%.
-- Another example: 80 -> 100 means (100 - 80) / 80 * 100 = 25% growth.
-- Do not COALESCE undefined growth to 0: unavailable growth is not zero growth.
-- Do not replace a missing first-row predecessor with zero and invent a comparison.


-- 07. Preserve calculation history before filtering displayed dates.
-- In the SAME query level, WHERE filters input before window functions execute.
-- If WHERE paid_date = November 4 were inside revenue_with_previous, LAG would
-- see only that date and return NULL. Instead filter the completed calculation.
-- WHERE is allowed with window queries; the issue is retaining needed history.

WITH daily_revenue (paid_date, revenue) AS (
    VALUES
        (DATE '2026-11-01', 100.00),
        (DATE '2026-11-02',   0.00),
        (DATE '2026-11-03',  50.00),
        (DATE '2026-11-04', 100.00)
),
revenue_with_previous AS (
    SELECT
        paid_date,
        revenue,
        LAG(revenue) OVER (ORDER BY paid_date) AS previous_day_revenue
    FROM daily_revenue
)
SELECT
    paid_date,
    revenue,
    previous_day_revenue,
    revenue - previous_day_revenue AS revenue_change,
    100.0 * (revenue - previous_day_revenue)
        / NULLIF(previous_day_revenue, 0) AS revenue_growth_pct
FROM revenue_with_previous
WHERE paid_date = DATE '2026-11-04'
ORDER BY paid_date;

-- Expected: one row for November 4, revenue 100, previous 50, change 50, growth 100%.
-- Calculation history can be larger than the display range. An input WHERE can
-- still limit irrelevant data, provided enough history remains for each metric.
-- A running total since inception needs different history from a short moving window.


-- 08. PARTITION BY calculates a separate running total for each channel.
-- Grain is now one row per channel per date, not one row per date overall.
-- PARTITION BY preserves rows; it does not collapse them like GROUP BY.
-- Dates are unique within each channel, even though they repeat across channels.

WITH daily_revenue (paid_date, channel, revenue) AS (
    VALUES
        (DATE '2026-11-01', 'Web', 100.00),
        (DATE '2026-11-02', 'Web',  50.00),
        (DATE '2026-11-01', 'App',  40.00),
        (DATE '2026-11-02', 'App',  60.00)
)
SELECT
    channel,
    paid_date,
    revenue,
    SUM(revenue) OVER (
        PARTITION BY channel
        ORDER BY paid_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_revenue
FROM daily_revenue
ORDER BY channel, paid_date;

-- Expected: App cumulative 40, 100; Web cumulative 100, 150.
-- Each partition starts from its own first row, without mixing channel revenue.


-- 09. Channel-specific LAG, change, and growth.
-- Each channel's growth must use its own previous revenue.
-- Omitting PARTITION BY would mix channels; equal dates would also create
-- ambiguous predecessor ordering unless an appropriate total order were supplied.
-- Multiple CTEs use one WITH and commas between definitions, not semicolons.
-- The last CTE ends with a closing parenthesis, then the main SELECT (no comma).

WITH daily_revenue (paid_date, channel, revenue) AS (
    VALUES
        (DATE '2026-11-01', 'Web', 100.00),
        (DATE '2026-11-02', 'Web',  50.00),
        (DATE '2026-11-01', 'App',  40.00),
        (DATE '2026-11-02', 'App',  60.00)
),
revenue_with_previous AS (
    SELECT
        channel,
        paid_date,
        revenue,
        LAG(revenue) OVER (
            PARTITION BY channel
            ORDER BY paid_date
        ) AS previous_day_revenue
    FROM daily_revenue
)
SELECT
    channel,
    paid_date,
    revenue,
    previous_day_revenue,
    revenue - previous_day_revenue AS revenue_change,
    100.0 * (revenue - previous_day_revenue)
        / NULLIF(previous_day_revenue, 0) AS revenue_growth_pct
FROM revenue_with_previous
ORDER BY channel, paid_date;

-- Expected: each channel's first row has NULL previous/change/growth.
-- App November 2: previous 40, change 20, growth 50%.
-- Web November 2: previous 100, change -50, growth -50%.


-- 10. Omitting the explicit frame does not mean having no frame.
-- For SUM/AVG with window ORDER BY, the default frame is:
-- RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
-- It includes all rows from the partition start through the current row's last
-- ORDER BY peer: rows equal on ALL window ordering expressions are peers.
-- For our daily channel data, dates are unique per partition, so deleting the
-- explicit cumulative ROWS frame produces the same SUM results.
-- This is not generally true when ordering values repeat.
-- With no window ORDER BY, the default frame includes the entire partition.
-- LAG uses partition ordering and its row offset, not this frame boundary.

-- Illustration of the duplicate-date distinction, using query-local sample entries.
-- entry_id provides deterministic row order for the explicit ROWS calculation.
-- The default RANGE calculation deliberately orders by DATE ONLY.

WITH entries (entry_id, paid_date, revenue) AS (
    VALUES
        (1, DATE '2026-11-01', 40.00),
        (2, DATE '2026-11-01', 10.00),
        (3, DATE '2026-11-02', 60.00)
)
SELECT
    entry_id,
    paid_date,
    revenue,
    SUM(revenue) OVER (
        ORDER BY paid_date
    ) AS default_range_total,
    SUM(revenue) OVER (
        ORDER BY paid_date, entry_id
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS row_by_row_total
FROM entries
ORDER BY paid_date, entry_id;

-- Expected default RANGE totals: 50, 50, 110; explicit ROWS totals: 40, 50, 110.
-- Both November 1 rows share the same date and are included together by RANGE.
-- Explicit ROWS alone does not resolve ties: use a meaningful tie-breaker when
-- ordering values are not unique, or aggregate to the intended grain first.


-- 11. Analytical window checklist.
-- Define what one row represents before selecting a window.
-- PARTITION BY: which entities or segments should be calculated independently?
-- Window ORDER BY: what is the calculation sequence, and is it deterministic?
-- Frame for SUM/AVG: which rows should contribute for each current row?
-- Query-level ORDER BY: how should the final result be displayed?
-- Distinguish row-based windows from calendar-based business definitions.
-- Decide whether partial windows are acceptable and how missing dates are handled.
-- Preserve enough history before applying final display filters.
-- Keep amount changes, percentage growth, missing predecessors, and zero baselines distinct.

-- PostgreSQL 18 references:
-- https://www.postgresql.org/docs/18/tutorial-window.html
-- https://www.postgresql.org/docs/18/functions-window.html
-- https://www.postgresql.org/docs/18/sql-expressions.html#SYNTAX-WINDOW-FUNCTIONS
-- https://www.postgresql.org/docs/18/functions-conditional.html#FUNCTIONS-NULLIF
