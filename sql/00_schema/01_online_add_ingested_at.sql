-- One-time migration for databases created before ingested_at columns existed.
-- Safe to re-run: ADD COLUMN IF NOT EXISTS / CREATE INDEX IF NOT EXISTS.

ALTER TABLE staging_user_orders ADD COLUMN IF NOT EXISTS ingested_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE staging_user_order_items ADD COLUMN IF NOT EXISTS ingested_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE staging_user_payments ADD COLUMN IF NOT EXISTS ingested_at TIMESTAMPTZ NOT NULL DEFAULT now();

ALTER TABLE final_user_orders ADD COLUMN IF NOT EXISTS ingested_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE final_user_order_items ADD COLUMN IF NOT EXISTS ingested_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE final_user_payments ADD COLUMN IF NOT EXISTS ingested_at TIMESTAMPTZ NOT NULL DEFAULT now();

ALTER TABLE users_feature_engineering ADD COLUMN IF NOT EXISTS ingested_at TIMESTAMPTZ NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_staging_user_orders_ingested_at ON staging_user_orders (ingested_at);
CREATE INDEX IF NOT EXISTS idx_staging_user_order_items_ingested_at ON staging_user_order_items (ingested_at);
CREATE INDEX IF NOT EXISTS idx_staging_user_payments_ingested_at ON staging_user_payments (ingested_at);

CREATE INDEX IF NOT EXISTS idx_final_user_orders_ingested_at ON final_user_orders (ingested_at);
CREATE INDEX IF NOT EXISTS idx_final_user_order_items_ingested_at ON final_user_order_items (ingested_at);
CREATE INDEX IF NOT EXISTS idx_final_user_payments_ingested_at ON final_user_payments (ingested_at);
CREATE INDEX IF NOT EXISTS idx_users_feature_engineering_ingested_at ON users_feature_engineering (ingested_at);
