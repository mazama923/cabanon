BEGIN;

CREATE TABLE IF NOT EXISTS schema_migrations (
  version integer PRIMARY KEY,
  name text NOT NULL,
  applied_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS construction_projects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL CHECK (btrim(name) <> ''),
  created_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO construction_projects (id, name)
VALUES ('00000000-0000-4000-8000-000000000001', 'My Home')
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS construction_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL REFERENCES construction_projects(id) ON DELETE RESTRICT,
  name text NOT NULL CHECK (btrim(name) <> ''),
  sort_order integer NOT NULL DEFAULT 100,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (project_id, id)
);

CREATE UNIQUE INDEX IF NOT EXISTS construction_categories_project_name_unique
  ON construction_categories (project_id, lower(btrim(name)));

INSERT INTO construction_categories (project_id, name, sort_order)
VALUES
  ('00000000-0000-4000-8000-000000000001', 'Construction', 10),
  ('00000000-0000-4000-8000-000000000001', 'Interior', 20),
  ('00000000-0000-4000-8000-000000000001', 'Exterior', 30)
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS construction_costs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL REFERENCES construction_projects(id) ON DELETE RESTRICT,
  category_id uuid NOT NULL,
  amount_cents bigint NOT NULL CHECK (amount_cents >= 0),
  incurred_on date NOT NULL,
  description text NOT NULL CHECK (btrim(description) <> ''),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (project_id, category_id)
    REFERENCES construction_categories(project_id, id)
    ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS construction_costs_project_history_idx
  ON construction_costs (project_id, incurred_on DESC, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS construction_costs_project_category_idx
  ON construction_costs (project_id, category_id);

INSERT INTO schema_migrations (version, name)
VALUES (1, 'construction_cost_history')
ON CONFLICT (version) DO NOTHING;

COMMIT;
