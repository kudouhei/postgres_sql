-- Lesson 04: Subqueries
-- Execute one complete statement at a time. All statements are read-only.
-- Examples assume these existing employees:
--   Alice: id 101, department 1 (Engineering), salary 5000
--   Bob:   id 102, department 1 (Engineering), salary 0
--   Carol: id 103, department 2 (Finance), salary 3000
-- Department 3 (Human Resources) has no employees. David was hypothetical.


-- 01. Scalar subquery: compare against one calculated value.
-- A scalar subquery must return one column and at most one row.
-- Zero rows produce NULL; more than one row causes an error.
-- AVG without GROUP BY returns one row, even when there are no input rows.
-- Find employees earning more than the company average.

SELECT id, name, salary
FROM employees
WHERE salary > (
    SELECT AVG(salary)
    FROM employees
)
ORDER BY id;


-- 02. Find all employees earning the company maximum.
-- MAX returns a salary value, not the first employee with that salary.
-- The outer query keeps every matching employee, including ties.
-- Replace MAX with MIN to find the lowest-paid employees.

SELECT id, name, salary
FROM employees
WHERE salary = (
    SELECT MAX(salary)
    FROM employees
)
ORDER BY id;

-- Do not use salary = (SELECT salary FROM employees) when it returns
-- multiple rows: the right-hand side of this scalar comparison needs one value.


-- 03. IN: match any value returned by a single-column subquery.
-- Find departments that have employees: Engineering and Finance.
-- Repeated department IDs in the subquery do not duplicate outer rows.
-- SELECT department_id IS NULL would return booleans, not department IDs.

SELECT d.id AS department_id, d.name AS department_name
FROM departments AS d
WHERE d.id IN (
    SELECT e.department_id
    FROM employees AS e
)
ORDER BY d.id;


-- 04. NOT IN: exclude values returned by the subquery.
-- Find departments with no employees: Human Resources.
-- Here, employees.department_id is NOT NULL, and departments.id is a primary key.
-- Do not assume this pattern is safe when the subquery can return NULL.

SELECT d.id AS department_id, d.name AS department_name
FROM departments AS d
WHERE d.id NOT IN (
    SELECT e.department_id
    FROM employees AS e
)
ORDER BY d.id;


-- 05. NOT IN and NULL: UNKNOWN is different from FALSE.
-- 2 NOT IN (1, NULL) is equivalent to 2 <> 1 AND 2 <> NULL.
-- TRUE AND UNKNOWN is UNKNOWN. WHERE keeps only TRUE, not UNKNOWN.
-- A definite match still makes NOT IN FALSE: FALSE AND UNKNOWN is FALSE.

SELECT
    2 NOT IN (1) AS without_null,          -- TRUE
    2 NOT IN (1, NULL) AS with_null,       -- NULL / UNKNOWN
    1 NOT IN (1, NULL) AS definite_match;  -- FALSE


-- 06. EXISTS with a correlated subquery.
-- EXISTS is TRUE if the subquery returns at least one row.
-- A correlated subquery references a value from the outer query.
-- e.department_id = d.id restricts the search to the current department.
-- SELECT 1 does not count rows or search for employee ID 1.
-- EXISTS checks whether rows exist, not the selected values.
-- Find departments with at least one employee earning 5000 or more.

SELECT d.id AS department_id, d.name AS department_name
FROM departments AS d
WHERE EXISTS (
    SELECT 1
    FROM employees AS e
    WHERE e.department_id = d.id
      AND e.salary >= 5000
)