import gleam/dynamic/decode
import gleam/json
import gleam/list
import pog

const household_budget_id = "00000000-0000-4000-8000-000000000002"

pub type HouseholdBudget {
  HouseholdBudget(
    people_count: Int,
    account_balance_cents: Int,
    expenses: List(ExpenseLine),
  )
}

pub type ExpenseLine {
  ExpenseLine(label: String, amount_cents: Int)
}

pub type StorageError {
  InvalidPeopleCount
  NegativeBalance
  NegativeExpense
  MissingBudget
  UnexpectedResultCount
  DatabaseError(pog.QueryError)
}

pub fn load(database: pog.Connection) -> Result(HouseholdBudget, StorageError) {
  let state_query =
    pog.query(
      "SELECT people_count, account_balance_cents, expense_count "
      <> "FROM household_budget_state WHERE id = $1::uuid",
    )
    |> pog.parameter(pog.text(household_budget_id))
    |> pog.returning(budget_state_decoder())

  case pog.execute(state_query, on: database) {
    Error(error) -> Error(DatabaseError(error))
    Ok(returned) ->
      case returned.rows {
        [#(people_count, account_balance_cents, expense_count)] ->
          case list_expenses(database, expense_count) {
            Ok(expenses) ->
              Ok(HouseholdBudget(
                people_count:,
                account_balance_cents:,
                expenses:,
              ))
            Error(error) -> Error(error)
          }
        [] -> Error(MissingBudget)
        _ -> Error(UnexpectedResultCount)
      }
  }
}

pub fn save(
  database: pog.Connection,
  budget: HouseholdBudget,
) -> Result(Nil, StorageError) {
  case validate_budget(budget) {
    Error(error) -> Error(error)
    Ok(Nil) -> save_valid_budget(database, budget)
  }
}

fn save_valid_budget(
  database: pog.Connection,
  budget: HouseholdBudget,
) -> Result(Nil, StorageError) {
  let HouseholdBudget(people_count, account_balance_cents, expenses) = budget
  let expenses_json =
    expenses
    |> list.map(expense_to_json)
    |> json.array(from: _, of: fn(value) { value })
    |> json.to_string

  let query =
    pog.query(
      "WITH saved_budget AS ("
      <> "INSERT INTO household_budget_state "
      <> "(id, people_count, account_balance_cents, expense_count) "
      <> "VALUES ($1::uuid, $2::integer, $3::bigint, "
      <> "jsonb_array_length($4::jsonb)) "
      <> "ON CONFLICT (id) DO UPDATE SET "
      <> "people_count = EXCLUDED.people_count, "
      <> "account_balance_cents = EXCLUDED.account_balance_cents, "
      <> "expense_count = EXCLUDED.expense_count, "
      <> "updated_at = now() RETURNING id"
      <> "), saved_expenses AS ("
      <> "INSERT INTO household_budget_expenses "
      <> "(budget_id, position, label, amount_cents) "
      <> "SELECT saved_budget.id, (entry.ordinality - 1)::integer, "
      <> "expense.label, expense.amount_cents "
      <> "FROM saved_budget "
      <> "CROSS JOIN LATERAL jsonb_array_elements($4::jsonb) "
      <> "WITH ORDINALITY AS entry(data, ordinality) "
      <> "CROSS JOIN LATERAL jsonb_to_record(entry.data) "
      <> "AS expense(label text, amount_cents bigint) "
      <> "ON CONFLICT (budget_id, position) DO UPDATE SET "
      <> "label = EXCLUDED.label, amount_cents = EXCLUDED.amount_cents"
      <> ") DELETE FROM household_budget_expenses "
      <> "WHERE budget_id = $1::uuid "
      <> "AND position >= jsonb_array_length($4::jsonb)",
    )
    |> pog.parameter(pog.text(household_budget_id))
    |> pog.parameter(pog.int(people_count))
    |> pog.parameter(pog.int(account_balance_cents))
    |> pog.parameter(pog.text(expenses_json))

  case pog.execute(query, on: database) {
    Ok(_) -> Ok(Nil)
    Error(error) -> Error(DatabaseError(error))
  }
}

fn list_expenses(
  database: pog.Connection,
  expense_count: Int,
) -> Result(List(ExpenseLine), StorageError) {
  let query =
    pog.query(
      "SELECT label, amount_cents FROM household_budget_expenses "
      <> "WHERE budget_id = $1::uuid AND position < $2::integer "
      <> "ORDER BY position",
    )
    |> pog.parameter(pog.text(household_budget_id))
    |> pog.parameter(pog.int(expense_count))
    |> pog.returning(expense_decoder())

  case pog.execute(query, on: database) {
    Ok(returned) -> Ok(returned.rows)
    Error(error) -> Error(DatabaseError(error))
  }
}

fn validate_budget(budget: HouseholdBudget) -> Result(Nil, StorageError) {
  case budget.people_count < 0 {
    True -> Error(InvalidPeopleCount)
    False ->
      case budget.account_balance_cents < 0 {
        True -> Error(NegativeBalance)
        False -> validate_expenses(budget.expenses)
      }
  }
}

fn validate_expenses(expenses: List(ExpenseLine)) -> Result(Nil, StorageError) {
  case expenses {
    [] -> Ok(Nil)
    [ExpenseLine(_, amount_cents), ..rest] ->
      case amount_cents < 0 {
        True -> Error(NegativeExpense)
        False -> validate_expenses(rest)
      }
  }
}

fn budget_state_decoder() -> decode.Decoder(#(Int, Int, Int)) {
  use people_count <- decode.subfield([0], decode.int)
  use account_balance_cents <- decode.subfield([1], decode.int)
  use expense_count <- decode.subfield([2], decode.int)
  decode.success(#(people_count, account_balance_cents, expense_count))
}

fn expense_decoder() -> decode.Decoder(ExpenseLine) {
  use label <- decode.subfield([0], decode.string)
  use amount_cents <- decode.subfield([1], decode.int)
  decode.success(ExpenseLine(label:, amount_cents:))
}

fn expense_to_json(expense: ExpenseLine) -> json.Json {
  let ExpenseLine(label:, amount_cents:) = expense
  json.object([
    #("label", json.string(label)),
    #("amount_cents", json.int(amount_cents)),
  ])
}
