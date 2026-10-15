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