BEGIN;

CREATE TABLE IF NOT EXISTS construction_cost_corrections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  construction_cost_id uuid NOT NULL
    REFERENCES construction_costs(id) ON DELETE RESTRICT,
  previous_category_id uuid NOT NULL
    REFERENCES construction_categories(id) ON DELETE RESTRICT,
  previous_amount_cents bigint NOT NULL CHECK (previous_amount_cents >= 0),
  previous_incurred_on date NOT NULL,
  previous_description text NOT NULL CHECK (btrim(previous_description) <> ''),
  reason text NOT NULL CHECK (btrim(reason) <> ''),
  corrected_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS construction_cost_corrections_history_idx
  ON construction_cost_corrections (construction_cost_id, corrected_at DESC, id DESC);

INSERT INTO schema_migrations (version, name)
VALUES (3, 'construction_cost_corrections')
ON CONFLICT (version) DO NOTHING;

COMMIT;
