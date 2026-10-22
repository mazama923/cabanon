BEGIN;

CREATE TABLE IF NOT EXISTS household_contribution_history (
  period date PRIMARY KEY CHECK (EXTRACT(DAY FROM period) = 1),
  people_count integer NOT NULL CHECK (people_count > 0),
  account_balance_cents bigint NOT NULL CHECK (account_balance_cents >= 0),
  expenses_total_cents bigint NOT NULL CHECK (expenses_total_cents >= 0),
  balance_applied_cents bigint NOT NULL CHECK (balance_applied_cents >= 0),
  remaining_balance_cents bigint NOT NULL CHECK (remaining_balance_cents >= 0),
  contribution_total_cents bigint NOT NULL CHECK (contribution_total_cents >= 0),
  base_share_cents bigint NOT NULL CHECK (base_share_cents >= 0),
  residents_paying_one_extra_cent integer NOT NULL
    CHECK (residents_paying_one_extra_cent >= 0
      AND residents_paying_one_extra_cent < people_count),
  saved_at timestamptz NOT NULL DEFAULT now(),
  CHECK (balance_applied_cents <= account_balance_cents),
  CHECK (balance_applied_cents <= expenses_total_cents),
  CHECK (remaining_balance_cents = account_balance_cents - balance_applied_cents),
  CHECK (contribution_total_cents = expenses_total_cents - balance_applied_cents),
  CHECK (
    contribution_total_cents =
      base_share_cents * people_count::bigint + residents_paying_one_extra_cent
  )
);

CREATE TABLE IF NOT EXISTS household_contribution_history_expenses (
  period date NOT NULL
    REFERENCES household_contribution_history(period) ON DELETE RESTRICT,
  position integer NOT NULL CHECK (position >= 0),
  label text NOT NULL,
  amount_cents bigint NOT NULL CHECK (amount_cents >= 0),
  PRIMARY KEY (period, position)
);

CREATE INDEX IF NOT EXISTS household_contribution_history_saved_at_idx
  ON household_contribution_history (saved_at DESC);

INSERT INTO schema_migrations (version, name)
VALUES (4, 'household_contribution_history')
ON CONFLICT (version) DO NOTHING;

COMMIT;
