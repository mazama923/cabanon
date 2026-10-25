# Data model

The schema includes executable migrations for construction history, a single local household budget, and immutable monthly contribution snapshots. Accounts, users, and multiple household ownership are future design work. All monetary values are stored as integer cents; the current application uses euros and is limited to one household.

## Household budgeting

The current implementation stores one active monthly household plan in a singleton budget state. The following entities describe a future multi-user model and are not implemented yet.

| Future entity | Important fields | Notes |
| --- | --- | --- |
| `households` | `id`, `name`, `currency`, `created_at` | Tenant boundary for every financial record |
| `users` | `id`, `email`, `password_hash`, `created_at` | One authenticated identity per person |
| `residents` | `id`, `household_id`, `user_id`, `display_name`, `active_from`, `active_until` | A contribution is calculated over active residents for a period |
| `expense_categories` | `id`, `household_id`, `name`, `kind` | Examples: groceries, utilities, rent, insurance |
| `expenses` | `id`, `household_id`, `category_id`, `amount_cents`, `incurred_on`, `description`, `created_by` | Immutable financial amount after confirmation; corrections use a reversal |
| `expense_splits` | `expense_id`, `resident_id`, `amount_cents` | Persist the calculated split so historical results remain reproducible |
| `payments` | `id`, `resident_id`, `amount_cents`, `paid_on`, `reference` | Record transfers to the joint account |

`expense_splits.amount_cents` must sum exactly to `expenses.amount_cents`. The domain function exposes the base share and the number of residents who pay one extra cent, avoiding rounding ambiguity.

Migration `0005` adds the active period and expense category/type fields. Existing budgets are assigned the database's current month; existing expense lines default to `Other` and are marked variable so users can review their estimates. For contribution planning, `plan_contributions` applies the available account balance to planned expenses first, up to the expense total. Contributions are calculated from the remainder and never become negative; any surplus balance is returned separately. The browser autosaves the active period, household size, account balance, and expense lines after a brief pause. Each line stores its label, one of the built-in categories, fixed/variable classification, and integer-cent estimate. When the browser opens a later calendar month, `POST /api/household/month` advances the singleton plan: it archives the previous plan when the household size permits a contribution calculation, carries its expense lines forward, and resets the shared-account balance to zero for manual review. The equal contribution calculation remains separate from the forecast total.

The monthly snapshot tables are `household_contribution_history` and `household_contribution_history_expenses`. The month is unique, the archived household size and balances are retained, and contribution results preserve the exact-cent equal split. Expense snapshots also retain category and fixed/variable classification. The API rejects duplicate months rather than overwriting a financial record. The current screen compares the active forecast with the immediately preceding calendar month only; it reports comparison as unavailable when that snapshot is missing or has a zero total. Percentages are derived for display and do not replace integer-cent amounts.

| Entity | Important fields | Notes |
| --- | --- | --- |
| `household_contribution_history` | `period`, household size, account balance, calculated totals and shares | One immutable contribution snapshot per month, saved manually or when advancing the active plan |
| `household_contribution_history_expenses` | `period`, `position`, `label`, `category`, `is_variable`, `amount_cents` | Expense details as entered when the monthly snapshot was saved |

## Construction cost history

The browser screen records actual costs only. Each entry has a date, description, category, and non-negative integer-cent amount. Record an invoice or purchase once; do not create duplicate entries for its instalments. The client shows the total and subtotals by category. Migration `0001` seeds one initial `My Home` project and the three default categories; the API and storage adapter persist costs. Corrections require a reason and save the previous values in `construction_cost_corrections`, so users can inspect the correction history without losing the current total.

| Entity | Important fields | Notes |
| --- | --- | --- |
| `construction_projects` | `id`, `name`, `created_at` | Migration seeds one project; household ownership is deferred until households exist |
| `construction_categories` | `id`, `project_id`, `name`, `sort_order`, `created_at` | User-defined categories, initially construction, interior, and exterior |
| `construction_costs` | `id`, `project_id`, `category_id`, `amount_cents`, `incurred_on`, `description`, `created_at` | Current version of one confirmed invoice or purchase; amount stored in integer cents |
| `construction_cost_corrections` | `id`, `construction_cost_id`, previous values, `reason`, `corrected_at` | Append-only snapshot of each version replaced by an explicit correction |

The initial project is not yet scoped to a household because accounts and households are not implemented. The API currently runs only on loopback and has no authentication; add household ownership, enforce household-scoped queries, and add authentication and authorization before allowing any external access. Estimate or forecast screens are future work. Cost corrections preserve the previous values and require a reason; financial history must not be silently deleted.

## Integrity rules

- Use UUID primary keys generated by PostgreSQL.
- Add `household_id` directly to tables that are frequently filtered by household, even where derivable; enforce it with foreign keys and indexes.
- Use `NOT NULL`, `CHECK (amount_cents >= 0)`, and foreign keys as close to the data as possible.
- Do not use `ON DELETE CASCADE` for financial records. Deactivate records or create explicit reversals.
- Add `created_at`, `updated_at`, and `created_by` to user-editable records.
- Keep uploaded invoices outside PostgreSQL if added later; store encrypted object metadata and a content hash in the database.
