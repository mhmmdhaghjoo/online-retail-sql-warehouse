-- 03_star_schema.sql
-- Dimensional model: one fact table at order-line grain and three
-- conformed dimensions. Unlike staging, everything here is constrained.

DROP SCHEMA IF EXISTS dw CASCADE;
CREATE SCHEMA dw;

CREATE TABLE dw.dim_date (
    date_key     integer PRIMARY KEY,           -- yyyymmdd
    full_date    date NOT NULL UNIQUE,
    year         smallint NOT NULL,
    quarter      smallint NOT NULL CHECK (quarter BETWEEN 1 AND 4),
    month        smallint NOT NULL CHECK (month BETWEEN 1 AND 12),
    month_start  date NOT NULL,
    month_name   text NOT NULL,
    iso_week     smallint NOT NULL,
    day_of_week  smallint NOT NULL CHECK (day_of_week BETWEEN 1 AND 7),  -- 1 = Monday
    is_weekend   boolean NOT NULL
);

CREATE TABLE dw.dim_customer (
    customer_key        integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id         integer UNIQUE,         -- business key; NULL only for the "unknown" member
    signup_date         date,
    country             char(2),                -- NULL = not recorded
    acquisition_channel text NOT NULL,
    birth_year          smallint CHECK (birth_year BETWEEN 1920 AND 2010)
);

CREATE TABLE dw.dim_product (
    product_key  integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id   text NOT NULL UNIQUE,
    product_name text NOT NULL,
    category     text NOT NULL,
    list_price   numeric(10, 2) NOT NULL CHECK (list_price > 0),
    unit_cost    numeric(10, 2) NOT NULL CHECK (unit_cost >= 0)
);

CREATE TABLE dw.fact_sales (
    sales_key    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id     text NOT NULL,                 -- degenerate dimension
    order_ts     timestamp NOT NULL,
    date_key     integer NOT NULL REFERENCES dw.dim_date (date_key),
    customer_key integer NOT NULL REFERENCES dw.dim_customer (customer_key),
    product_key  integer NOT NULL REFERENCES dw.dim_product (product_key),
    quantity     integer NOT NULL CHECK (quantity > 0),
    unit_price   numeric(10, 2) NOT NULL CHECK (unit_price > 0),
    discount_pct numeric(4, 2) NOT NULL CHECK (discount_pct >= 0 AND discount_pct < 1),
    net_revenue  numeric(12, 2) NOT NULL,       -- quantity * unit_price * (1 - discount)
    cost         numeric(12, 2) NOT NULL,       -- quantity * unit_cost
    UNIQUE (order_id, product_key)
);
