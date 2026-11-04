-- Lesson 13: Data Grain and JOIN Correctness for Data Science
-- English reference notes. All statements are read-only and self-contained.
-- Execute one complete WITH ... SELECT statement at a time.
-- VALUES creates query-local sample rows, not permanent tables or inserted data.
-- CTE names exist only within their statement, so definitions are repeated below.
-- Assumptions: orders are paid; order_amount is whole-order revenue, without refunds.
-- item_count counts detail ROWS, not product quantities or distinct products.
-- Sample stages: two orders = 150; three orders = 250; four orders = 330.


-- 01. Establish the grain and a baseline before joining.
-- Data grain asks: what does one row represent?
-- orders: one row per order; order_items: one row per item/detail record.

WITH orders (order_id, order_amount) AS (
    VALUES (1001, 100.00), (1002, 50.00)
)
SELECT SUM(order_amount) AS total_revenue
FROM orders;

-- Expected: 150.00. If only total order revenue is needed, no detail JOIN is required.


-- 02. One-to-many JOINs can repeat order-level measures: join fanout.
-- An INNER JOIN returns one row per matching pair, not one per left-side row.
-- Order 1001 matches Keyboard AND Mouse, so its amount appears twice.
-- The JOIN is valid; summing its repeated order amounts answers the wrong question.

WITH orders (order_id, order_amount) AS (
    VALUES (1001, 100.00), (1002, 50.00)
),
order_items (item_id, order_id, product_name) AS (
    VALUES
        (1, 1001, 'Keyboard'),
        (2, 1001, 'Mouse'),
        (3, 1002, 'Notebook')
)
SELECT
    COUNT(*) AS joined_rows,
    SUM(o.order_amount) AS incorrect_revenue
FROM orders AS o
JOIN order_items AS i
    ON i.order_id = o.order_id;

-- Expected: 3 rows summed, incorrect revenue 250.00 = 100 + 100 + 50.
-- Correct revenue remains 150.00. Repeated output does not create real orders.
-- The row (2, 1001, 'Mouse') means item 2 belongs to ORDER 1001, not order 1002.
-- With this order-ID condition, three matching details produce three result rows.


-- 03. SUM(DISTINCT amount) is not a general repair.
-- DISTINCT inside SUM deduplicates numeric VALUES, not business entities.
-- Different orders can legitimately have the same amount.

WITH orders (order_id, order_amount) AS (
    VALUES (1001, 100.00), (1002, 50.00), (1003, 100.00)
)
SELECT
    SUM(order_amount) AS total_revenue,
    SUM(DISTINCT order_amount) AS distinct_amount_sum
FROM orders;

-- Expected: 250.00 versus 150.00. Both 100-valued orders must count.
-- Deduplicate by the relevant business key when needed, not by the measure.


-- 04. Use EXISTS when details are needed only to qualify orders.
-- Requirement: whole-order revenue for orders containing Keyboard OR Mouse.
-- This is NOT the revenue attributable only to those individual products.
-- Correlation i.order_id = o.order_id restricts the test to the current order.
-- IN supplies the accepted product names; both predicates must hold.
-- SELECT 1 is a convention: EXISTS checks for rows, not their selected values.
-- Two matching details still retain an outer order only once.

WITH orders (order_id, order_amount) AS (
    VALUES (1001, 100.00), (1002, 50.00), (1003, 100.00)
),
order_items (item_id, order_id, product_name) AS (
    VALUES
        (1, 1001, 'Keyboard'),
        (2, 1001, 'Mouse'),
        (3, 1002, 'Notebook'),
        (4, 1003, 'Keyboard')
)
SELECT SUM(o.order_amount) AS qualified_order_revenue
FROM orders AS o
WHERE EXISTS (
    SELECT 1
    FROM order_items AS i
    WHERE i.order_id = o.order_id
      AND i.product_name IN ('Keyboard', 'Mouse')
);

-- Expected: 200.00 from orders 1001 and 1003, each contributing 100 once.
-- Order 1002 has an item, but Notebook does not satisfy the product condition.
-- To inspect qualifying orders, replace the outer SUM with o.order_id,
-- o.order_amount and optionally add ORDER BY o.order_id.


-- 05. Aggregate detail rows to order grain when detail measures are needed.
-- GROUP BY order_id produces one row per order represented in the detail input.

WITH order_items (item_id, order_id, product_name) AS (
    VALUES
        (1, 1001, 'Keyboard'),
        (2, 1001, 'Mouse'),
        (3, 1002, 'Notebook'),
        (4, 1003, 'Keyboard')
)
SELECT order_id, COUNT(*) AS item_count
FROM order_items
GROUP BY order_id
ORDER BY order_id;

-- Expected: (1001, 2), (1002, 1), (1003, 1).
-- Aggregation changes the grain from one item row to one order summary row.


-- 06. Join the order-grain summary, then calculate totals.
-- Both sides have one row per order ID, avoiding the previous fanout.
-- This sample has details for every order; that completeness is checked later.

WITH orders (order_id, order_amount) AS (
    VALUES (1001, 100.00), (1002, 50.00), (1003, 100.00)
),
order_items (item_id, order_id, product_name) AS (
    VALUES
        (1, 1001, 'Keyboard'),
        (2, 1001, 'Mouse'),
        (3, 1002, 'Notebook'),
        (4, 1003, 'Keyboard')
),
item_counts AS (
    SELECT order_id, COUNT(*) AS item_count
    FROM order_items
    GROUP BY order_id
)
SELECT
    SUM(o.order_amount) AS total_revenue,
    SUM(ic.item_count) AS total_item_count
FROM orders AS o
JOIN item_counts AS ic
    ON ic.order_id = o.order_id;

-- Expected: revenue 250.00; item count 4 = 2 + 1 + 1.
-- No outer GROUP BY is needed because this SELECT requests one overall summary.
-- COUNT(*) here would count joined order rows (3), not the detail rows (4).
-- To inspect each order instead, select o.order_id, o.order_amount, ic.item_count
-- rather than the SUM expressions, and add ORDER BY o.order_id.


-- 07. COALESCE supplies the first non-NULL value, from left to right.
-- Zero is a value, not NULL. All-NULL arguments produce NULL.
-- Arguments must be convertible to a common data type.

SELECT
    COALESCE(NULL, 0) AS null_with_fallback,
    COALESCE(2, 0) AS existing_value,
    COALESCE(0, 99) AS zero_is_preserved;

-- Expected: 0, 2, 0. In a SELECT this changes output values, not stored rows.


-- 08. Prevent missing orders as well as duplicated orders.
-- Add paid order 1004, amount 80, but no loaded details: assume a sync delay.
-- INNER JOIN would exclude it because item_counts has no corresponding row.
-- LEFT JOIN preserves the order and supplies NULL for unmatched summary columns.

WITH orders (order_id, order_amount) AS (
    VALUES
        (1001, 100.00), (1002, 50.00),
        (1003, 100.00), (1004, 80.00)
),
order_items (item_id, order_id, product_name) AS (
    VALUES
        (1, 1001, 'Keyboard'),
        (2, 1001, 'Mouse'),
        (3, 1002, 'Notebook'),
        (4, 1003, 'Keyboard')
),
item_counts AS (
    SELECT order_id, COUNT(*) AS item_count
    FROM order_items
    GROUP BY order_id
)
SELECT
    o.order_id,
    o.order_amount,
    ic.item_count AS original_item_count,
    COALESCE(ic.item_count, 0) AS display_item_count
FROM orders AS o
LEFT JOIN item_counts AS ic
    ON ic.order_id = o.order_id
ORDER BY o.order_id;

-- Expected rows: (1001, 100, 2, 2), (1002, 50, 1, 1),
--                (1003, 100, 1, 1), (1004, 80, NULL, 0).
-- COUNT did not calculate NULL for 1004: no group for that order was produced.
-- LEFT JOIN introduced NULL because the summary row was missing.
-- The displayed zero is an explicit fallback, NOT proof of zero actual items.
-- Choose INNER/LEFT based on the question; LEFT JOIN is not universally preferable.


-- 09. Validate coverage before interpreting aggregate measures.
-- At this joined grain COUNT(*) counts all orders and COUNT(ic.order_id) counts
-- matched orders, because the latter ignores the unmatched NULL values.
-- This relies on the right side having at most one summary row per order ID.

WITH orders (order_id, order_amount) AS (
    VALUES
        (1001, 100.00), (1002, 50.00),
        (1003, 100.00), (1004, 80.00)
),
order_items (item_id, order_id, product_name) AS (
    VALUES
        (1, 1001, 'Keyboard'),
        (2, 1001, 'Mouse'),
        (3, 1002, 'Notebook'),
        (4, 1003, 'Keyboard')
),
item_counts AS (
    SELECT order_id, COUNT(*) AS item_count
    FROM order_items
    GROUP BY order_id
)
SELECT
    COUNT(*) AS total_orders,
    COUNT(ic.order_id) AS matched_orders,
    COUNT(*) - COUNT(ic.order_id) AS unmatched_orders,
    SUM(o.order_amount) AS total_order_revenue,
    SUM(ic.item_count) AS observed_item_count
FROM orders AS o
LEFT JOIN item_counts AS ic
    ON ic.order_id = o.order_id;

-- Expected: 4 total, 3 matched, 1 unmatched, revenue 330.00, observed items 4.
-- The extended check adds revenue/item totals to the coverage query we practiced.
-- Order match rate: 3 / 4 = 75%. This is NOT the percentage of all items loaded.
-- Actual item count across all four orders is unknown while 1004's data is missing.
-- SUM ignores NULL inputs; it does not certify completeness. With no non-NULL
-- inputs, SUM returns NULL, not zero. COUNT(*) still counts unmatched left rows.


-- 10. DS SQL correctness checklist.
-- Define the entity, time window, filters, and measure before coding.
-- State each input's grain and the expected output grain.
-- Identify which join keys are unique and how many matches are possible.
-- Use EXISTS for existence-based qualification without expanding outer rows.
-- Pre-aggregate when a detail measure must be joined at a coarser grain.
-- Verify both duplicate expansion and missing matches against a baseline.
-- Do not repair entity duplication by deduplicating equal measure values.
-- Keep observed counts, unknown values, and meaningful zeroes distinct.
-- Report coverage alongside metrics when missing data affects interpretation.
-- Executable SQL is not necessarily analytically correct SQL.

-- PostgreSQL 18 references:
-- https://www.postgresql.org/docs/18/queries-table-expressions.html
-- https://www.postgresql.org/docs/18/functions-subquery.html
-- https://www.postgresql.org/docs/18/functions-conditional.html
-- https://www.postgresql.org/docs/18/functions-aggregate.html
