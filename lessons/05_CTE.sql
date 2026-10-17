-- Lesson 05: Common Table Expressions (CTEs)
-- Execute one complete statement at a time. All statements are read-only.
-- Example data:
--   Engineering (1): Alice, salary 5000; Bob, salary 0.
--   Finance (2): Carol, salary 3000.
--   Human Resources (3): no employees.


-- 01. Define a CTE with WITH name AS (...).
-- A CTE names a query result for use within the same SQL statement.
-- It does not create a permanent table or remain available to later statements.
-- Do not put a semicolon between the CTE definition and the main query.
-- Here, GROUP BY produces one maximum salary per department with employees.

WITH department_max AS (
    SELECT
        department_id,
        MAX(salary) AS max_salary
    FROM employees
    GROUP BY department_id
)
SELECT
    department_id,
    max_salary
FROM department_max
ORDER BY department_id;

-- Expected: department 1 -> 5000; department 2 -> 3000.
-- Human Resources is absent because the CTE reads only from employees.


-- 02. Join a CTE to employee details.
-- Find all highest-paid employees in each department.
-- Match BOTH the department ID and the salary to that department's maximum.
-- Matching only department IDs would also keep employees below the maximum.
-- Matching only salaries would not establish that the departments are the same.
-- Ties within a department are all included.

WITH department_max AS (
    SELECT
        department_id,
        MAX(salary) AS max_salary
    FROM employees
    GROUP BY department_id
)
SELECT
    e.id,
    e.name,
    e.department_id,
    e.salary
FROM employees AS e
INNER JOIN department_max AS dm
    ON e.department_id = dm.department_id
   AND e.salary = dm.max_salary
ORDER BY e.id;

-- Expected: Alice (5000) and Carol (3000).
-- The CTE calculates department-level values; the JOIN finds matching employees.


-- 03. Compare employee salaries against department averages.
-- The CTE groups employees; the outer query keeps employee-level detail.
-- No outer GROUP BY is needed because the outer query does not aggregate.
-- Table aliases are arbitrary: use any valid name consistently.

WITH department_avg AS (
    SELECT
        department_id,
        AVG(salary) AS avg_salary
    FROM employees
    GROUP BY department_id
)
SELECT
    e.id,
    e.name,
    e.department_id,
    e.salary
FROM employees AS e
INNER JOIN department_avg AS da
    ON e.department_id = da.department_id
   AND e.salary > da.avg_salary
ORDER BY e.id;

-- Expected: Alice only, because 5000 > 2500.
-- Bob: 0 < 2500. Carol: 3000 = 3000, so she does not pass the strict > test.


-- 04. Reference one CTE multiple times in the same statement.
-- Find departments with the highest average salary and include their names.
-- The outer FROM reads department averages; the scalar subquery finds their maximum.
-- The JOIN supplies department names from departments.
-- This compares department averages, not individual employee salaries.
-- Equality preserves all departments tied for the highest average.

WITH department_avg AS (
    SELECT
        department_id,
        AVG(salary) AS avg_salary
    FROM employees
    GROUP BY department_id
)
SELECT
    d.id AS department_id,
    d.name AS department_name,
    da.avg_salary
FROM department_avg AS da
INNER JOIN departments AS d
    ON d.id = da.department_id
WHERE da.avg_salary = (
    SELECT MAX(avg_salary)
    FROM department_avg
)
ORDER BY department_id;

-- Expected: Finance (2), average salary 3000.
-- Engineering's average is 2500, even though Alice has the highest individual salary.
-- In the scalar subquery, MAX(avg_salary) reads its own department_avg input.
-- Do not replace it with MAX(da.avg_salary), which refers to the outer query.
-- ORDER BY department_id uses the output column alias defined in SELECT.
-- AVG and MAX ignore NULL inputs; comparisons against NULL do not evaluate to TRUE.
