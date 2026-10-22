import cabanon/domain/household/budget as domain_budget
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/string
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

pub type ContributionHistoryEntry {
  ContributionHistoryEntry(
    period: String,
    people_count: Int,
    account_balance_cents: Int,
    expenses_total_cents: Int,
    balance_applied_cents: Int,
    remaining_balance_cents: Int,
    contribution_total_cents: Int,
    base_share_cents: Int,
    residents_paying_one_extra_cent: Int,
    expenses: List(ExpenseLine),
  )
}

type ContributionHistoryHeader {
  ContributionHistoryHeader(
    period: String,
    people_count: Int,
    account_balance_cents: Int,
    expenses_total_cents: Int,
    balance_applied_cents: Int,
    remaining_balance_cents: Int,
    contribution_total_cents: Int,
    base_share_cents: Int,
    residents_paying_one_extra_cent: Int,
  )
}

pub type StorageError {
  InvalidPeopleCount
  NegativeBalance
  NegativeExpense
  MissingBudget
  InvalidHistoryPeriod
  InvalidHistoryPeopleCount
  DuplicateHistoryPeriod
  InvalidHistoryCalculation(domain_budget.CalculationError)
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

pub fn archive_contributions(
  database: pog.Connection,
  period: String,
  budget: HouseholdBudget,
) -> Result(ContributionHistoryEntry, StorageError) {
  case valid_period(period) {
    False -> Error(InvalidHistoryPeriod)
    True ->
      case budget.people_count <= 0 {
        True -> Error(InvalidHistoryPeopleCount)
        False ->
          case validate_budget(budget) {
            Error(error) -> Error(error)
            Ok(Nil) -> archive_valid_contributions(database, period, budget)
          }
      }
  }
}

pub fn list_contribution_history(
  database: pog.Connection,
) -> Result(List(ContributionHistoryEntry), StorageError) {
  let query =
    pog.query(
      "SELECT to_char(period, 'YYYY-MM'), people_count, "
      <> "account_balance_cents, expenses_total_cents, "
      <> "balance_applied_cents, remaining_balance_cents, "
      <> "contribution_total_cents, base_share_cents, "
      <> "residents_paying_one_extra_cent "
      <> "FROM household_contribution_history ORDER BY period DESC",
    )
    |> pog.returning(contribution_history_header_decoder())

  case pog.execute(query, on: database) {
    Error(error) -> Error(DatabaseError(error))
    Ok(returned) -> load_history_entries(database, returned.rows)
  }
}

fn archive_valid_contributions(
  database: pog.Connection,
  period: String,
  budget: HouseholdBudget,
) -> Result(ContributionHistoryEntry, StorageError) {
  let HouseholdBudget(people_count, account_balance_cents, expenses) = budget
  let domain_expenses =
    list.map(expenses, fn(expense) {
      let ExpenseLine(_, amount_cents) = expense
      domain_budget.Expense(amount_cents)
    })
  case
    domain_budget.plan_contributions(
      domain_expenses,
      account_balance_cents,
      people_count,
    )
  {
    Error(error) -> Error(InvalidHistoryCalculation(error))
    Ok(plan) -> {
      let domain_budget.ContributionPlan(
        expenses_total_cents,
        balance_applied_cents,
        remaining_balance_cents,
        contribution_total_cents,
        base_share_cents,
        residents_paying_one_extra_cent,
      ) = plan
      let expenses_json =
        expenses
        |> list.map(expense_to_json)
        |> json.array(from: _, of: fn(value) { value })
        |> json.to_string
      let query =
        pog.query(
          "WITH archived AS ("
          <> "INSERT INTO household_contribution_history ("
          <> "period, people_count, account_balance_cents, "
          <> "expenses_total_cents, balance_applied_cents, "
          <> "remaining_balance_cents, contribution_total_cents, "
          <> "base_share_cents, residents_paying_one_extra_cent) "
          <> "VALUES (($1::text || '-01')::date, $2::integer, $3::bigint, "
          <> "$4::bigint, $5::bigint, $6::bigint, $7::bigint, "
          <> "$8::bigint, $9::integer) "
          <> "ON CONFLICT (period) DO NOTHING RETURNING period"
          <> "), saved_expenses AS ("
          <> "INSERT INTO household_contribution_history_expenses "
          <> "(period, position, label, amount_cents) "
          <> "SELECT archived.period, (entry.ordinality - 1)::integer, "
          <> "expense.label, expense.amount_cents FROM archived "
          <> "CROSS JOIN LATERAL jsonb_array_elements($10::jsonb) "
          <> "WITH ORDINALITY AS entry(data, ordinality) "
          <> "CROSS JOIN LATERAL jsonb_to_record(entry.data) "
          <> "AS expense(label text, amount_cents bigint) "
          <> "RETURNING period) "
          <> "SELECT archived.period::text FROM archived "
          <> "CROSS JOIN (SELECT count(*) FROM saved_expenses) AS written",
        )
        |> pog.parameter(pog.text(period))
        |> pog.parameter(pog.int(people_count))
        |> pog.parameter(pog.int(account_balance_cents))
        |> pog.parameter(pog.int(expenses_total_cents))
        |> pog.parameter(pog.int(balance_applied_cents))
        |> pog.parameter(pog.int(remaining_balance_cents))
        |> pog.parameter(pog.int(contribution_total_cents))
        |> pog.parameter(pog.int(base_share_cents))
        |> pog.parameter(pog.int(residents_paying_one_extra_cent))
        |> pog.parameter(pog.text(expenses_json))
        |> pog.returning(decode.at([0], decode.string))

      case pog.execute(query, on: database) {
        Error(error) -> Error(DatabaseError(error))
        Ok(returned) ->
          case returned.rows {
            [_] -> load_contribution_history(database, period)
            [] -> Error(DuplicateHistoryPeriod)
            _ -> Error(UnexpectedResultCount)
          }
      }
    }
  }
}

fn load_history_entries(
  database: pog.Connection,
  headers: List(ContributionHistoryHeader),
) -> Result(List(ContributionHistoryEntry), StorageError) {
  case headers {
    [] -> Ok([])
    [header, ..rest] ->
      case load_history_entry(database, header) {
        Error(error) -> Error(error)
        Ok(entry) ->
          case load_history_entries(database, rest) {
            Error(error) -> Error(error)
            Ok(entries) -> Ok([entry, ..entries])
          }
      }
  }
}

fn load_contribution_history(
  database: pog.Connection,
  period: String,
) -> Result(ContributionHistoryEntry, StorageError) {
  let query =
    pog.query(
      "SELECT to_char(period, 'YYYY-MM'), people_count, "
      <> "account_balance_cents, expenses_total_cents, "
      <> "balance_applied_cents, remaining_balance_cents, "
      <> "contribution_total_cents, base_share_cents, "
      <> "residents_paying_one_extra_cent "
      <> "FROM household_contribution_history "
      <> "WHERE period = ($1::text || '-01')::date",
    )
    |> pog.parameter(pog.text(period))
    |> pog.returning(contribution_history_header_decoder())

  case pog.execute(query, on: database) {
    Error(error) -> Error(DatabaseError(error))
    Ok(returned) ->
      case returned.rows {
        [header] -> load_history_entry(database, header)
        _ -> Error(UnexpectedResultCount)
      }
  }
}

fn load_history_entry(
  database: pog.Connection,
  header: ContributionHistoryHeader,
) -> Result(ContributionHistoryEntry, StorageError) {
  let ContributionHistoryHeader(
    period,
    people_count,
    account_balance_cents,
    expenses_total_cents,
    balance_applied_cents,
    remaining_balance_cents,
    contribution_total_cents,
    base_share_cents,
    residents_paying_one_extra_cent,
  ) = header
  let query =
    pog.query(
      "SELECT label, amount_cents "
      <> "FROM household_contribution_history_expenses "
      <> "WHERE period = ($1::text || '-01')::date ORDER BY position",
    )
    |> pog.parameter(pog.text(period))
    |> pog.returning(expense_decoder())

  case pog.execute(query, on: database) {
    Error(error) -> Error(DatabaseError(error))
    Ok(returned) ->
      Ok(ContributionHistoryEntry(
        period:,
        people_count:,
        account_balance_cents:,
        expenses_total_cents:,
        balance_applied_cents:,
        remaining_balance_cents:,
        contribution_total_cents:,
        base_share_cents:,
        residents_paying_one_extra_cent:,
        expenses: returned.rows,
      ))
  }
}

fn valid_period(period: String) -> Bool {
  case string.split(period, on: "-") {
    [year, month] ->
      case string.length(year) == 4 && string.length(month) == 2 {
        False -> False
        True ->
          case int.parse(year), int.parse(month) {
            Ok(year_number), Ok(month_number) ->
              year_number > 0
              && month_number >= 1
              && month_number <= 12
              && only_digits(string.to_graphemes(year))
              && only_digits(string.to_graphemes(month))
            _, _ -> False
          }
      }
    _ -> False
  }
}

fn only_digits(characters: List(String)) -> Bool {
  case characters {
    [] -> True
    [character, ..rest] ->
      case int.parse(character) {
        Ok(value) if value >= 0 && value <= 9 -> only_digits(rest)
        _ -> False
      }
  }
}

fn contribution_history_header_decoder() -> decode.Decoder(
  ContributionHistoryHeader,
) {
  use period <- decode.subfield([0], decode.string)
  use people_count <- decode.subfield([1], decode.int)
  use account_balance_cents <- decode.subfield([2], decode.int)
  use expenses_total_cents <- decode.subfield([3], decode.int)
  use balance_applied_cents <- decode.subfield([4], decode.int)
  use remaining_balance_cents <- decode.subfield([5], decode.int)
  use contribution_total_cents <- decode.subfield([6], decode.int)
  use base_share_cents <- decode.subfield([7], decode.int)
  use residents_paying_one_extra_cent <- decode.subfield([8], decode.int)
  decode.success(ContributionHistoryHeader(
    period:,
    people_count:,
    account_balance_cents:,
    expenses_total_cents:,
    balance_applied_cents:,
    remaining_balance_cents:,
    contribution_total_cents:,
    base_share_cents:,
    residents_paying_one_extra_cent:,
  ))
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
