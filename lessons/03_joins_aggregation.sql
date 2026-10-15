-- Joins, grouping, aggregates, NULL, and CASE

-- docker compose up -d --wait

-- 01. INNER JOIN：只返回满足连接条件的组合。
-- INNER JOIN returns combinations of rows that satisfy the join condition.
-- Table aliases shorten references; column aliases name the output columns.
-- A foreign key does not automatically supply the join condition.

SELECT
    e.id AS employee_id,
    e.name AS employee_name,
    d.name AS department_name
FROM employees AS e
INNER JOIN departments AS d
    ON e.department_id = d.id
ORDER BY e.id;

-- 02. LEFT JOIN：保留左侧所有行；未匹配的右表字段补为 NULL。
-- LEFT JOIN preserves left-side rows and fills unmatched right-side columns with NULL.
-- The left side in this query is departments.
-- These NULLs are produced by the join, not inserted into employees.
-- Two matching employees produce two rows; joining does not aggregate them.

SELECT
    d.id AS department_id,
    d.name AS department_name,
    e.id AS employee_id,
    e.name AS employee_name,
    e.salary
FROM departments AS d
LEFT JOIN employees AS e
    ON e.department_id = d.id
ORDER BY d.id, e.id;

-- 03. 找出没有员工的部门 / Find departments with no employees.
-- A real employee ID cannot be NULL, so a NULL here identifies an unmatched row.
-- Use IS NULL, not = NULL, to test for NULL.

SELECT
    d.id AS department_id,
    d.name AS department_name
FROM departments AS d
LEFT JOIN employees AS e
    ON e.department_id = d.id
WHERE e.id IS NULL
ORDER BY d.id;


-- 04. ON 与 WHERE / ON versus WHERE.
-- ON 决定怎样匹配；WHERE 对连接后的结果行进行筛选（逻辑语义）。
-- ON controls matching; WHERE filters the joined result logically.

SELECT
    d.id AS department_id,
    d.name AS department_name,
    e.name AS employee_name
FROM departments AS d
LEFT JOIN employees AS e
    ON e.department_id = d.id
   AND e.name = 'Bob'
WHERE d.id IN (1, 2)
ORDER BY d.id;

-- 05. 整体聚合 / Aggregate the whole table.
-- Without GROUP BY, this query summarizes the whole employee table as one group.
-- COUNT(*) counts rows; COUNT(salary) counts non-null salary values.
-- SUM, AVG, MIN, and MAX ignore NULL but include zero.
-- Earlier, with Bob's salary NULL, COUNT(salary) was 1 and AVG(salary) was 5000.
-- AVG uses the number of non-null salary values as its denominator.

SELECT
    COUNT(*) AS employee_count,
    COUNT(salary) AS known_salary_count,
    SUM(salary) AS total_known_salary,
    AVG(salary) AS average_known_salary,
    MIN(salary) AS minimum_salary,
    MAX(salary) AS maximum_salary
FROM employees;

-- 06. GROUP BY：每个部门分别汇总 / Summarize each department separately.
-- GROUP BY 决定哪些明细行属于同一组，聚合函数决定每组算什么。
-- GROUP BY defines the groups; aggregate functions calculate results per group.
-- This query explicitly groups by department ID and name.
-- Engineering has two joined rows; each unmatched department has one NULL-extended row.
-- COUNT(e.id) returns 0 for unmatched departments; COUNT(*) would count the row as 1.
-- SUM/AVG/MIN/MAX return NULL when they have no non-null input values.

SELECT
    d.id AS department_id,
    d.name AS department_name,
    COUNT(e.id) AS employee_count,
    COUNT(e.salary) AS known_salary_count,
    SUM(e.salary) AS total_known_salary,
    AVG(e.salary) AS average_known_salary,
    MIN(e.salary) AS minimum_salary,
    MAX(e.salary) AS maximum_salary
FROM departments AS d
LEFT JOIN employees AS e
    ON e.department_id = d.id
GROUP BY d.id, d.name
ORDER BY d.id;

-- 07. WHERE 与 HAVING / Row filters versus group filters.
-- WHERE filters rows before grouping; HAVING filters groups after aggregation.
-- Find departments with zero employees among departments 1 and 2.

SELECT
    d.id AS department_id,
    d.name AS department_name,
    COUNT(e.id) AS employee_count
FROM departments AS d
LEFT JOIN employees AS e
    ON e.department_id = d.id
WHERE d.id IN (1, 2)
GROUP BY d.id, d.name
HAVING COUNT(e.id) = 0
ORDER BY d.id;

-- 08. HAVING 也可以筛选 MIN/SUM/AVG 等统计值。
-- HAVING can filter other aggregates, including MIN, SUM, and AVG.

SELECT
    d.id AS department_id,
    d.name AS department_name,
    MIN(e.salary) AS minimum_salary,
    MAX(e.salary) AS maximum_salary
FROM departments AS d
LEFT JOIN employees AS e
    ON e.department_id = d.id
GROUP BY d.id, d.name
HAVING MIN(e.salary) = 0
ORDER BY d.id;

-- 09. COALESCE：返回第一个非 NULL 的参数，不是聚合函数。
-- COALESCE returns the first non-null argument; it is not an aggregate function.
-- Zero and empty strings are values, so they are not replaced.

SELECT
    COALESCE(NULL, 0) AS replace_null,
    COALESCE(0, 100) AS keep_zero,
    COALESCE('', 'fallback') AS keep_empty_string;


SELECT
    d.id AS department_id,
    d.name AS department_name,
    COUNT(e.id) AS employee_count,
    COALESCE(SUM(e.salary), 0) AS total_known_salary,
    AVG(e.salary) AS average_known_salary
FROM departments AS d
LEFT JOIN employees AS e
    ON e.department_id = d.id
GROUP BY d.id, d.name
ORDER BY d.id;

-- 10. CASE：刚引入，待继续练习 / Newly introduced; further practice pending.
-- CASE uses the branch for the first condition that evaluates to TRUE.
-- ELSE handles the remaining cases; END closes the expression.
-- This query classifies individual employees without aggregation.
-- salary_status is a computed output column, not a new stored column.

SELECT
    id,
    name,
    salary,
    CASE
        WHEN salary IS NULL THEN 'Unknown'
        WHEN salary = 0 THEN 'Zero salary'
        ELSE 'Positive salary'
    END AS salary_status
FROM employees
ORDER BY id;

-- CASE and Conditional Aggregation

-- CASE returns a value based on conditions.

SELECT
    id,
    name,
    salary,
    CASE
        WHEN salary IS NULL THEN 'Unknown'
        WHEN salary = 0 THEN 'Zero salary'
        WHEN salary >= 5000 THEN 'High salary'
        ELSE 'Regular salary'
    END AS salary_level
FROM employees
ORDER BY id;


-- Test every branch without changing stored data.
--
-- VALUES：提供本次查询使用的测试数据。
-- NULL::numeric：将 NULL 指定为 numeric 类型。
-- NULLS FIRST：排序时将 NULL 放在最前面。

SELECT
    salary,
    CASE
        WHEN salary IS NULL THEN 'Unknown'
        WHEN salary = 0 THEN 'Zero salary'
        WHEN salary >= 5000 THEN 'High salary'
        ELSE 'Regular salary'
    END AS salary_level
FROM (
    VALUES
        (NULL::numeric),
        (0),
        (3000),
        (5000)
) AS test_data(salary)
ORDER BY salary NULLS FIRST;


SELECT
    id,
    name,
    salary,
    CASE
        WHEN salary > 0 THEN id
        ELSE NULL
    END AS id_to_count
FROM employees
ORDER BY id;


-- 四、COUNT 与 SUM 的条件统计
-- Conditional counting with COUNT and SUM.
--
-- COUNT counts non-NULL values, including zero.
--
-- SUM adds non-NULL numeric values.
--


SELECT
    COUNT(*) AS employee_count,

    COUNT(
        CASE
            WHEN salary > 0 THEN id
            ELSE NULL
        END
    ) AS positive_salary_count_by_count,

    SUM(
        CASE
            WHEN salary > 0 THEN 1
            ELSE 0
        END
    ) AS positive_salary_count_by_sum
FROM employees;

-- 五、在一条查询中进行多个条件统计
-- Calculate multiple conditional aggregates in one query.
--
-- Each CASE evaluates each row independently.

SELECT
    COUNT(*) AS employee_count,
    SUM(
        CASE
            WHEN salary = 0 THEN 1
            ELSE 0
        END
    ) AS zero_salary_count,
    SUM(
        CASE
            WHEN salary >= 5000 THEN 1
            ELSE 0
        END
    ) AS high_salary_count
FROM employees;

-- 当前预期：
-- employee_count = 2
-- zero_salary_count = 1
-- high_salary_count = 1


-- 六、按部门进行条件统计
-- Conditional aggregation per department.
--
-- LEFT JOIN：保留所有部门。
-- GROUP BY：每个部门形成一个组。
-- COUNT(e.id)：统计实际员工，不统计补出的 NULL 员工行。
-- SUM(CASE ...)：在各部门组内进行条件统计。

SELECT
    d.id AS department_id,
    d.name AS department_name,
    COUNT(e.id) AS employee_count,

    SUM(
        CASE
            WHEN e.salary >= 5000 THEN 1
            ELSE 0
        END
    ) AS high_salary_count
FROM departments AS d
LEFT JOIN employees AS e
    ON e.department_id = d.id
GROUP BY d.id, d.name
ORDER BY d.id;


-- Why does SUM return zero for departments without employees?
--
-- LEFT JOIN 为该部门保留一行，员工字段为 NULL。
-- NULL >= 5000 的结果是 UNKNOWN，不是 TRUE。
-- CASE 因而选择 ELSE 0，SUM 的输入就包含一个 0。
-- NULL is not zero.