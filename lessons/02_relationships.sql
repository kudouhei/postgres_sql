-- Lesson 2: Foreign keys and one-to-many relationships

CREATE TABLE employees (
    id integer PRIMARY KEY,
    name text NOT NULL,
    department_id integer NOT NULL
        REFERENCES departments(id)
);

INSERT INTO employees (id, name, department_id)
VALUES
    (101, 'Alice', 1),
    (102, 'Bob', 1);

SELECT id, name, department_id
FROM employees
ORDER BY id;

-- Foreign keys allow repeated referencing values.
-- 外键列允许重复，因此多名员工可以属于同一个部门。

-- NOT NULL makes the relationship mandatory.
-- NOT NULL 要求每名员工必须填写部门编号。

-- The default ON DELETE action is NO ACTION.
-- 默认删除策略为 NO ACTION。