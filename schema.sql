-- =====================================================
-- schema.sql : ShopKart e-commerce database (MySQL 8.0+)
-- =====================================================
DROP DATABASE IF EXISTS shopkart_db;
CREATE DATABASE shopkart_db;
USE shopkart_db;

CREATE TABLE customers (
    customer_id         INT PRIMARY KEY,
    full_name           VARCHAR(100) NOT NULL,
    email               VARCHAR(120) NOT NULL UNIQUE,
    gender              VARCHAR(10),
    city                VARCHAR(50),
    state               VARCHAR(50),
    signup_date         DATE NOT NULL,
    acquisition_channel VARCHAR(30) NOT NULL
);

CREATE TABLE products (
    product_id    INT PRIMARY KEY,
    product_name  VARCHAR(100) NOT NULL,
    category      VARCHAR(30)  NOT NULL,
    brand         VARCHAR(50)  NOT NULL,
    cost_price    DECIMAL(10,2) NOT NULL,
    mrp           DECIMAL(10,2) NOT NULL
);

CREATE TABLE orders (
    order_id        INT PRIMARY KEY,
    customer_id     INT NOT NULL,
    order_date      DATE NOT NULL,
    order_status    VARCHAR(20) NOT NULL,   -- Delivered / Shipped / Cancelled / Returned
    payment_method  VARCHAR(30) NOT NULL,
    delivery_days   INT NULL,
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

CREATE TABLE order_items (
    order_item_id INT PRIMARY KEY,
    order_id      INT NOT NULL,
    product_id    INT NOT NULL,
    quantity      INT NOT NULL,
    unit_price    DECIMAL(10,2) NOT NULL,   -- selling price before discount
    discount_pct  INT NOT NULL DEFAULT 0,
    FOREIGN KEY (order_id)   REFERENCES orders(order_id),
    FOREIGN KEY (product_id) REFERENCES products(product_id)
);

CREATE TABLE reviews (
    review_id   INT PRIMARY KEY,
    product_id  INT NOT NULL,
    customer_id INT NOT NULL,
    order_id    INT NOT NULL,
    rating      INT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    review_date DATE NOT NULL,
    FOREIGN KEY (product_id)  REFERENCES products(product_id),
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
    FOREIGN KEY (order_id)    REFERENCES orders(order_id)
);

CREATE TABLE marketing_spend (
    spend_id     INT PRIMARY KEY,
    spend_month  DATE NOT NULL,             -- first day of month
    channel      VARCHAR(30) NOT NULL,
    spend_amount DECIMAL(12,2) NOT NULL
);

CREATE INDEX idx_orders_date     ON orders(order_date);
CREATE INDEX idx_orders_customer ON orders(customer_id);
CREATE INDEX idx_items_order     ON order_items(order_id);
CREATE INDEX idx_items_product   ON order_items(product_id);
