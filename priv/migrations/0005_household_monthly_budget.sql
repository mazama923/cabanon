BEGIN;

ALTER TABLE household_budget_state
  ADD COLUMN IF NOT EXISTS period date NOT NULL
    DEFAULT date_trunc('month', CURRENT_DATE)::date;

ALTER TABLE household_budget_expenses
  ADD COLUMN IF NOT EXISTS category text NOT NULL DEFAULT 'Other',
  ADD COLUMN IF NOT EXISTS is_variable boolean NOT NULL DEFAULT true;

ALTER TABLE household_contribution_history_expenses
  ADD COLUMN IF NOT EXISTS category text NOT NULL DEFAULT 'Other',
  ADD COLUMN IF NOT EXISTS is_variable boolean NOT NULL DEFAULT true;

INSERT INTO schema_migrations (version, name)
VALUES (5, 'household_monthly_budget')
ON CONFLICT (version) DO NOTHING;

COMMIT;
