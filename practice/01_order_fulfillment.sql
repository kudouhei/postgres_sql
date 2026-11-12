-- Practice 01: Reliable Order and Shipment Reporting
-- English reference notes. Every executable statement is read-only and self-contained.
-- Run one complete WITH ... SELECT or SELECT statement at a time.
-- VALUES supplies query-local test data; it does not create or modify real tables.
-- CTE definitions are repeated because they exist only within their statement.
-- Business scope: all non-cancelled orders, including orders not yet shipped.
-- Required totals: orders, order amount, shipments, recorded shipping cost,
-- and shipment records whose shipping cost is missing.
-- Assumptions: order_id and shipment_id are unique and non-NULL in their inputs;
-- status is non-NULL; shipping_cost may be NULL. Real datasets need these checks.
-- orders grain: one row per order. shipments grain: one row per shipment.


-- 01. Establish an order-only baseline before joining.
-- Three paid orders qualify; the cancelled order does not.
-- Do not replace "non-cancelled" with "paid" without confirming all possible statuses.

WITH orders (order_id, status, order_amount) AS (
    VALUES
        (1001, 'paid',      100.00),
        (1002, 'paid',       50.00),
        (1003, 'paid',       80.00),
        (1004, 'cancelled',  40.00)
)
SELECT
    COUNT(*) AS order_count,
    SUM(order_amount) AS total_order_amount
FROM orders
WHERE status <> 'cancelled';

-- Expected: 3 orders, total order amount 230.


-- 02. Inspect the raw LEFT JOIN before aggregating: one-to-many fanout.
-- JOIN syntax uses LEFT JOIN, no preceding comma, and = rather than ==.
-- ON defines shipment matches; WHERE applies the order-status business filter.
-- Qualify order_id with an alias because both inputs contain that column.

WITH orders (order_id, status, order_amount) AS (
    VALUES
        (1001, 'paid',      100.00),
        (1002, 'paid',       50.00),
        (1003, 'paid',       80.00),
        (1004, 'cancelled',  40.00)
),
shipments (shipment_id, order_id, shipping_cost) AS (
    VALUES
        (501, 1001, 8.00),
        (502, 1001, 5.00),
        (503, 1002, 6.00)
)
SELECT
    o.order_id,
    o.order_amount,
    s.shipment_id,
    s.shipping_cost
FROM orders AS o
LEFT JOIN shipments AS s
    ON o.order_id = s.order_id
WHERE o.status <> 'cancelled'
ORDER BY o.order_id, s.shipment_id;

-- Expected: two rows for 1001, one for 1002, and one unmatched row for 1003.
-- The unmatched shipment columns are NULL, not evidence of free shipping.
-- If aggregated directly, COUNT(*) would be 4 and SUM(o.order_amount) would be 330.
-- The extra 100 is the repeated amount of order 1001. The source order was not modified.
-- Three shipment records belong to only TWO shipped orders.
-- An INNER JOIN would lose unshipped order 1003 and violate the reporting scope.


-- 03. Aggregate shipments to one row per order.
-- GROUP BY order_id establishes the required summary grain.
-- Sort the grouped result by order_id, not an ungrouped shipment_id.
-- Adding shipment_id to GROUP BY would incorrectly split the summary again.

WITH shipments (shipment_id, order_id, shipping_cost) AS (
    VALUES
        (501, 1001, 8.00),
        (502, 1001, 5.00),
        (503, 1002, 6.00)
)
SELECT
    s.order_id,
    COUNT(*) AS shipment_count,
    SUM(s.shipping_cost) AS total_shipping_cost
FROM shipments AS s
GROUP BY s.order_id
ORDER BY s.order_id;

-- Expected: (1001, 2, 13), (1002, 1, 6).
-- Aggregation preserves shipment counts and costs; it does not discard real shipments.


-- 04. Join the order-grain summary, preserving one row per eligible order.
-- Each unique order matches at most one shipment-summary row.
-- No outer GROUP BY is needed when simply displaying the order-level results.

WITH orders (order_id, status, order_amount) AS (
    VALUES
        (1001, 'paid',      100.00),
        (1002, 'paid',       50.00),
        (1003, 'paid',       80.00),
        (1004, 'cancelled',  40.00)
),
shipments (shipment_id, order_id, shipping_cost) AS (
    VALUES
        (501, 1001, 8.00),
        (502, 1001, 5.00),
        (503, 1002, 6.00)
),
shipment_summary AS (
    SELECT
        order_id,
        COUNT(*) AS shipment_count,
        SUM(shipping_cost) AS total_shipping_cost
    FROM shipments
    GROUP BY order_id
)
SELECT
    o.order_id,
    o.order_amount,
    COALESCE(s.shipment_count, 0) AS shipment_count,
    s.total_shipping_cost
FROM orders AS o
LEFT JOIN shipment_summary AS s
    ON o.order_id = s.order_id
WHERE o.status <> 'cancelled'
ORDER BY o.order_id;

-- Expected: (1001, 100, 2, 13), (1002, 50, 1, 6), (1003, 80, 0, NULL).
-- COUNT did not produce NULL for 1003: its shipment group never existed.
-- LEFT JOIN introduced the NULL; COALESCE displays the absent shipment count as 0.
-- Keep its recorded cost NULL rather than claiming a known zero charge.


-- 05. Add a new order and a shipment with a missing charge, then summarize safely.
-- Order 1005 has the SAME amount as 1001 but is a separate business entity.
-- Deduplicating equal amounts with SUM(DISTINCT order_amount) is not a valid repair.
-- Shipment 504 exists, but its cost has not arrived: NULL is not a zero charge.
-- COUNT(*) - COUNT(shipping_cost) counts actual shipments with missing costs.
-- Compute this BEFORE the LEFT JOIN so an unshipped order is not mistaken for
-- one actual shipment whose cost is missing.

WITH orders (order_id, status, order_amount) AS (
    VALUES
        (1001, 'paid',      100.00),
        (1002, 'paid',       50.00),
        (1003, 'paid',       80.00),
        (1004, 'cancelled',  40.00),
        (1005, 'paid',      100.00)
),
shipments (shipment_id, order_id, shipping_cost) AS (
    VALUES
        (501, 1001, 8.00),
        (502, 1001, 5.00),
        (503, 1002, 6.00),
        (504, 1005, NULL)
),
shipment_summary AS (
    SELECT
        order_id,
        COUNT(*) AS shipment_count,
        COUNT(*) - COUNT(shipping_cost) AS missing_shipping_cost_count,
        SUM(shipping_cost) AS total_shipping_cost
    FROM shipments
    GROUP BY order_id
)
SELECT
    COUNT(o.order_id) AS order_count,
    SUM(o.order_amount) AS total_order_amount,
    SUM(COALESCE(s.shipment_count, 0)) AS total_shipments,
    SUM(s.total_shipping_cost) AS total_recorded_shipping_cost,
    SUM(COALESCE(s.missing_shipping_cost_count, 0)) AS missing_shipping_cost_count
FROM orders AS o
LEFT JOIN shipment_summary AS s
    ON o.order_id = s.order_id
WHERE o.status <> 'cancelled';

-- Expected: 4 orders, amount 330, 4 shipments, recorded cost 19, 1 missing cost.
-- SUM ignores NULL inputs: 19 is the recorded amount, NOT a complete actual total.
-- Inner aggregation: one count per order. Outer aggregation: SUM those counts.
-- COALESCE replaces each missing value; it does not itself aggregate multiple rows.
-- This outer query requests one overall row: do not GROUP BY or ORDER BY order_id.

-- Why COUNT(order_id) - COUNT(known_cost_count) was wrong:
-- An order-level known_cost_count of 0 is non-NULL, so COUNT still counts that row.
-- That expression counts unmatched orders, not shipment records with missing costs.
-- It happened to return 1 because 1003 was unshipped, not because 1005 lacked a charge.
-- Alternative valid strategy: SUM(shipment_count) - SUM(known_cost_count), with
-- unmatched summary counts treated as 0. SUM adds counts; COUNT counts their rows.


-- 06. Unknown cost and known zero cost have different meanings.
-- With rows present but all costs unknown, SUM(cost) is NULL.
-- Filling each cost with zero before SUM instead reports zero and loses that distinction.

WITH charges (shipping_cost) AS (
    VALUES (NULL::numeric), (NULL::numeric)
)
SELECT
    SUM(shipping_cost) AS recorded_cost,
    SUM(COALESCE(shipping_cost, 0)) AS cost_with_zero_fallback
FROM charges;

-- Expected: NULL versus 0. A business definition may explicitly choose a fallback,
-- but unknown charges should still be reported separately, not silently called free.


-- 07. Counterexample validation: complete the missing charge without changing the logic.
-- This is the final confirmed sample state: shipment 504 now has a known cost of 4.
-- Order 1003 remains unshipped, so a correct missing-cost metric must become zero.

WITH orders (order_id, status, order_amount) AS (
    VALUES
        (1001, 'paid',      100.00),
        (1002, 'paid',       50.00),
        (1003, 'paid',       80.00),
        (1004, 'cancelled',  40.00),
        (1005, 'paid',      100.00)
),
shipments (shipment_id, order_id, shipping_cost) AS (
    VALUES
        (501, 1001, 8.00),
        (502, 1001, 5.00),
        (503, 1002, 6.00),
        (504, 1005, 4.00)
),
shipment_summary AS (
    SELECT
        order_id,
        COUNT(*) AS shipment_count,
        COUNT(*) - COUNT(shipping_cost) AS missing_shipping_cost_count,
        SUM(shipping_cost) AS total_shipping_cost
    FROM shipments
    GROUP BY order_id
)
SELECT
    COUNT(o.order_id) AS order_count,
    SUM(o.order_amount) AS total_order_amount,
    SUM(COALESCE(s.shipment_count, 0)) AS total_shipments,
    SUM(s.total_shipping_cost) AS total_recorded_shipping_cost,
    SUM(COALESCE(s.missing_shipping_cost_count, 0)) AS missing_shipping_cost_count
FROM orders AS o
LEFT JOIN shipment_summary AS s
    ON o.order_id = s.order_id
WHERE o.status <> 'cancelled';

-- Expected: 4 orders, amount 330, 4 shipments, recorded cost 23, 0 missing costs.
-- Test matrix, with columns (orders, order amount, shipments, recorded cost, missing costs):
-- Original sample without order 1005 or shipment 504:          (3, 230, 3, 19, 0).
-- Add only order 1005 with amount 100, no shipment for it:     (4, 330, 3, 19, 0).
-- Add shipment 504 for 1005 with cost NULL:                    (4, 330, 4, 19, 1).
-- Complete shipment 504's cost as 4:                          (4, 330, 4, 23, 0).
-- Reproduce stages by editing only the CTE sample rows, not the reporting logic.
-- SQL that returns the right number on one dataset can still have the wrong meaning.


-- 08. Review checklist and English explanation.
-- Define the input and output grain before writing the JOIN.
-- Establish an order-only baseline and preserve its totals when adding shipment data.
-- Aggregate the many-side data to the intended join key before joining measures.
-- Preserve eligible orders without shipments using LEFT JOIN.
-- Separate row-level substitutions from aggregate calculations.
-- Distinguish unshipped orders, missing shipment charges, and known zero charges.
-- Test repeated order amounts and changing cost completeness, not just normal rows.
-- Further edge case: with NO eligible orders, COUNT returns 0 but SUM returns NULL,
-- even for SUM(COALESCE(..., 0)), because there are no input rows to replace.
-- Decide empty-population reporting rules explicitly rather than assuming all sums are 0.
-- English: "I aggregate shipments by order_id before the LEFT JOIN, so each order
-- matches at most one summary row. This prevents order amounts from being counted
-- multiple times. I report missing charges separately from the recorded cost total."

-- PostgreSQL references:
-- https://www.postgresql.org/docs/18/queries-table-expressions.html
-- https://www.postgresql.org/docs/18/functions-aggregate.html
-- https://www.postgresql.org/docs/18/functions-conditional.html
