-- ============================================================
-- Financial Services Analytics Platform
-- Schema: Customer Segmentation & Transaction Analytics
-- Target engine: MySQL 8.0+ (run in MySQL Workbench)
-- ============================================================

CREATE DATABASE IF NOT EXISTS financial_analytics;
USE financial_analytics;

DROP TABLE IF EXISTS fraud_flags;
DROP TABLE IF EXISTS transactions;
DROP TABLE IF EXISTS cards;
DROP TABLE IF EXISTS merchants;
DROP TABLE IF EXISTS merchant_categories;
DROP TABLE IF EXISTS branches;
DROP TABLE IF EXISTS customers;

-- ---------------------------------------------------------
-- BRANCHES : physical bank branches used to originate cards
-- ---------------------------------------------------------
CREATE TABLE branches (
    branch_id       INT AUTO_INCREMENT PRIMARY KEY,
    branch_name     VARCHAR(100) NOT NULL,
    city            VARCHAR(60)  NOT NULL,
    state           VARCHAR(60)  NOT NULL,
    region          VARCHAR(30)  NOT NULL,
    opened_date     DATE
);

-- ---------------------------------------------------------
-- CUSTOMERS : core customer master
-- ---------------------------------------------------------
CREATE TABLE customers (
    customer_id     INT AUTO_INCREMENT PRIMARY KEY,
    first_name      VARCHAR(50)  NOT NULL,
    last_name       VARCHAR(50)  NOT NULL,
    email           VARCHAR(120) UNIQUE,
    gender          VARCHAR(10),
    date_of_birth   DATE,
    city            VARCHAR(60),
    state           VARCHAR(60),
    income_bracket  VARCHAR(20),
    signup_date     DATE NOT NULL,
    branch_id       INT,
    FOREIGN KEY (branch_id) REFERENCES branches(branch_id)
);

-- ---------------------------------------------------------
-- CARDS : one customer can hold multiple cards
-- ---------------------------------------------------------
CREATE TABLE cards (
    card_id         INT AUTO_INCREMENT PRIMARY KEY,
    customer_id     INT NOT NULL,
    card_type       VARCHAR(20)  NOT NULL,
    card_network    VARCHAR(20)  NOT NULL,
    credit_limit    DECIMAL(12,2),
    issue_date      DATE NOT NULL,
    expiry_date     DATE NOT NULL,
    is_active       BOOLEAN DEFAULT TRUE,
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

-- ---------------------------------------------------------
-- MERCHANT_CATEGORIES
-- ---------------------------------------------------------
CREATE TABLE merchant_categories (
    category_id     INT AUTO_INCREMENT PRIMARY KEY,
    category_name   VARCHAR(60) NOT NULL,
    category_group  VARCHAR(30) NOT NULL
);

-- ---------------------------------------------------------
-- MERCHANTS
-- ---------------------------------------------------------
CREATE TABLE merchants (
    merchant_id     INT AUTO_INCREMENT PRIMARY KEY,
    merchant_name   VARCHAR(120) NOT NULL,
    category_id     INT NOT NULL,
    city            VARCHAR(60),
    state           VARCHAR(60),
    risk_level      VARCHAR(10) DEFAULT 'Low',
    FOREIGN KEY (category_id) REFERENCES merchant_categories(category_id)
);

-- ---------------------------------------------------------
-- TRANSACTIONS : the fact table
-- ---------------------------------------------------------
CREATE TABLE transactions (
    transaction_id      BIGINT AUTO_INCREMENT PRIMARY KEY,
    card_id             INT NOT NULL,
    customer_id         INT NOT NULL,
    merchant_id         INT NOT NULL,
    transaction_date    DATETIME NOT NULL,
    transaction_amount  DECIMAL(12,2) NOT NULL,
    transaction_type    VARCHAR(20) NOT NULL,
    transaction_status  VARCHAR(20) NOT NULL,
    is_fraud            BOOLEAN DEFAULT FALSE,
    FOREIGN KEY (card_id) REFERENCES cards(card_id),
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
    FOREIGN KEY (merchant_id) REFERENCES merchants(merchant_id)
);

-- ---------------------------------------------------------
-- FRAUD_FLAGS
-- ---------------------------------------------------------
CREATE TABLE fraud_flags (
    flag_id             INT AUTO_INCREMENT PRIMARY KEY,
    transaction_id      BIGINT NOT NULL,
    fraud_score         DECIMAL(5,2),
    flag_reason         VARCHAR(120),
    flagged_at          DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (transaction_id) REFERENCES transactions(transaction_id)
);

-- ---------------------------------------------------------
-- Indexes for analytical query performance
-- ---------------------------------------------------------
CREATE INDEX idx_transactions_customer ON transactions(customer_id);
CREATE INDEX idx_transactions_card     ON transactions(card_id);
CREATE INDEX idx_transactions_merchant ON transactions(merchant_id);
CREATE INDEX idx_transactions_date     ON transactions(transaction_date);
CREATE INDEX idx_transactions_status   ON transactions(transaction_status);
CREATE INDEX idx_cards_customer        ON cards(customer_id);
CREATE INDEX idx_merchants_category    ON merchants(category_id);
