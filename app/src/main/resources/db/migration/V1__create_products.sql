-- V1: criação inicial da tabela products e sequence
-- Gerado a partir do modelo Product.java (JPA → Flyway migration)
CREATE SEQUENCE IF NOT EXISTS product_seq
    START WITH 1
    INCREMENT BY 50
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
CREATE TABLE IF NOT EXISTS products (
    id         BIGINT       NOT NULL DEFAULT nextval('product_seq'),
    name       VARCHAR(255) NOT NULL,
    price      NUMERIC(38, 2) NOT NULL,
    stock      INTEGER,
    created_at TIMESTAMPTZ  NOT NULL,
    CONSTRAINT pk_products PRIMARY KEY (id)
);
