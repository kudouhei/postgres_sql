-- Lesson 06: Window Functions and Ranking
-- Execute one complete statement at a time. All statements are read-only.
-- Stored data: Alice (101, department 1, salary 5000),
-- Bob (102, department 1, salary 0), Carol (103, department 2, salary 3000).
-- David appears only in the VALUES sample, not in the employees table.


-- 01. Window aggregates preserve individual rows.
-- GROUP BY department_id produces one summary row per department.
-- AVG(...) OVER (...) keeps each employee row and adds an average beside it.
-- PARTITION BY defines which rows belong to the same calculation partition.
-- OVER () puts all input rows into one partition.
-- These AVG windows have no ORDER BY, so each uses its entire partition.

SELECT
    id,
    name,
    department_id,
    salary,
    AVG(salary) OVER (
        PARTITION BY department_id
    ) AS department_average_salary,
    AVG(salary) OVER () AS company_average_salary
FROM employees
ORDER BY id;

-- Expected: three employee rows, not one row per department.
-- Alice and Bob: department average 2500. Carol: department average 3000.
-- Company average: approximately 2666.67 for all three employees.
-- AVG ignores NULL salaries but includes zero salaries.

-- 02. Calculate window values first; filter them in an outer query.
-- A window function cannot be used directly in WHERE at the same query level.
-- An output alias defined in SELECT is also unavailable in that level's WHERE.
-- The CTE exposes the calculated average as an input column to the outer query.

WITH employee_salary_stats AS (
    SELECT
        id,
        name,
        department_id,
        salary,
        AVG(salary) OVER (
            PARTITION BY department_id
        ) AS department_average_salary
    FROM employees
)
SELECT
    id,
    name,
    department_id,
    salary,
    department_average_salary
FROM employee_salary_stats
WHERE salary > department_average_salary
ORDER BY id;

-- Expected: Alice, salary 5000, department average 2500.
-- Bob still contributes to that average even though the outer WHERE excludes him.
-- Change > to < to find below-average employees: Bob.
-- A WHERE inside the CTE would filter its input before the window calculation.


-- 03. ROW_NUMBER: assign a different sequential number to each row.
-- PARTITION BY department_id restarts numbering for each department.
-- Window ORDER BY determines numbering: highest salary first, then lowest ID.
-- With equal salaries, ID provides a deterministic tie-breaker.
-- The outer WHERE selects exactly one employee per department present in the input.
-- Current salaries are non-NULL; for nullable salaries, DESC NULLS LAST puts
-- unknown salaries after known salaries rather than before them.

WITH ranked_employees AS (
    SELECT
        id,
        name,
        department_id,
        salary,
        ROW_NUMBER() OVER (
            PARTITION BY department_id
            ORDER BY salary DESC, id
        ) AS salary_position
    FROM employees
)
SELECT
    id,
    name,
    department_id,
    salary,
    salary_position
FROM ranked_employees
WHERE salary_position = 1
ORDER BY department_id;

-- Expected: Alice and Carol.
-- Remove the outer WHERE to see every employee's number.
-- ROW_NUMBER does not preserve all employees tied for the highest salary.


-- 04. Compare ROW_NUMBER, RANK, and DENSE_RANK using temporary sample rows.
-- VALUES supplies query-local data; it does not insert employees.
-- ROW_NUMBER: unique row numbers, even when salaries tie.
-- RANK: equal salaries share a rank; later ranks have gaps.
-- DENSE_RANK: equal salaries share a rank; later ranks have no gaps.
-- For salary-based ties, RANK and DENSE_RANK order only by salary, not by ID.
-- Adding ID to their window ordering would break equal-salary ties.

WITH ranked_sample AS (
    SELECT
        id,
        name,
        salary,
        ROW_NUMBER() OVER (
            PARTITION BY department_id
            ORDER BY salary DESC, id
        ) AS salary_position,
        RANK() OVER (
            PARTITION BY department_id
            ORDER BY salary DESC
        ) AS salary_rank,
        DENSE_RANK() OVER (
            PARTITION BY department_id
            ORDER BY salary DESC
        ) AS dense_salary_rank
    FROM (
        VALUES
            (101, 'Alice', 1, 5000),
            (104, 'David', 1, 5000),
            (102, 'Bob',   1, 0)
    ) AS sample(id, name, department_id, salary)
)
SELECT
    id,
    name,
    salary,
    salary_position,
    salary_rank,
    dense_salary_rank
FROM ranked_sample
WHERE dense_salary_rank <= 2
ORDER BY dense_salary_rank, id;

-- Expected:
-- name  | salary | salary_position | salary_rank | dense_salary_rank
-- Alice |   5000 |               1 |           1 |                 1
-- David |   5000 |               2 |           1 |                 1
-- Bob   |      0 |               3 |           3 |                 2
--
-- Choose the outer filter according to the requirement:
-- WHERE salary_position = 1     -> one employee: Alice.
-- WHERE salary_rank = 1         -> all tied highest-paid employees: Alice, David.
-- WHERE salary_position <= 2    -> first two rows: Alice, David.
-- WHERE salary_rank <= 2        -> competition ranks up to 2: Alice, David.
-- WHERE dense_salary_rank <= 2  -> top two distinct salary levels: all three.
-- Replace the existing WHERE; do not add a second WHERE.
--
-- A salary of zero is still a salary level: it is the second-highest here.
-- Ranking values come from the function, not from the output alias after AS.
-- Window ORDER BY determines ranks; outer ORDER BY determines display order.
-- ORDER BY id would display Alice, Bob, David without changing their ranks.