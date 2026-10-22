BEGIN;

CREATE TABLE IF NOT EXISTS household_budget_state (
  id uuid PRIMARY KEY CHECK (id = '00000000-0000-4000-8000-000000000002'),
  people_count integer NOT NULL DEFAULT 0 CHECK (people_count >= 0),
  account_balance_cents bigint NOT NULL DEFAULT 0 CHECK (account_balance_cents >= 0),
  expense_count integer NOT NULL DEFAULT 0 CHECK (expense_count >= 0),
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO household_budget_state (id)
VALUES ('00000000-0000-4000-8000-000000000002')
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS household_budget_expenses (
  budget_id uuid NOT NULL REFERENCES household_budget_state(id) ON DELETE RESTRICT,
  position integer NOT NULL CHECK (position >= 0),
  label text NOT NULL DEFAULT '',
  amount_cents bigint NOT NULL CHECK (amount_cents >= 0),
  PRIMARY KEY (budget_id, position)
);

INSERT INTO schema_migrations (version, name)
VALUES (2, 'household_budget_autosave')
ON CONFLICT (version) DO NOTHING;

COMMIT;
