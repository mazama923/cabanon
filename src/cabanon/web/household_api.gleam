import cabanon/persistence/household_budget as persistence
import cabanon/web/api_response
import gleam/bit_array
import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/json
import pog
import wisp

pub fn handle(
  request: wisp.Request,
  database: pog.Connection,
) -> wisp.Response {
  let response = case request.method {
    http.Options -> wisp.response(204)
    http.Get -> load_budget(database)
    http.Put -> save_budget(request, database)
    _ -> wisp.method_not_allowed(allowed: [http.Get, http.Put, http.Options])
  }

  api_response.with_headers(response, request)
}

pub fn handle_history(
  request: wisp.Request,
  database: pog.Connection,
) -> wisp.Response {
  let response = case request.method {
    http.Options -> wisp.response(204)
    http.Get -> load_history(database)
    http.Post -> archive_history(request, database)
    _ -> wisp.method_not_allowed(allowed: [http.Get, http.Post, http.Options])
  }
  api_response.with_headers(response, request)
}

pub fn unavailable(request: wisp.Request) -> wisp.Response {
  let response = case request.method {
    http.Options -> wisp.response(204)
    _ -> json_error(503, "The household database is unavailable.")
  }
  api_response.with_headers(response, request)
}

fn load_history(database: pog.Connection) -> wisp.Response {
  case persistence.list_contribution_history(database) {
    Ok(entries) ->
      respond_json(
        200,
        json.array(from: entries, of: contribution_history_to_json),
      )
    Error(_) -> json_error(500, "The household history could not be loaded.")
  }
}

fn archive_history(
  request: wisp.Request,
  database: pog.Connection,
) -> wisp.Response {
  case json_request_body(request) {
    Error(response) -> response
    Ok(body) ->
      case json.parse(body, contribution_archive_decoder()) {
        Error(_) -> json_error(400, "Invalid household history request body.")
        Ok(#(period, budget)) ->
          case persistence.archive_contributions(database, period, budget) {
            Ok(entry) -> respond_json(201, contribution_history_to_json(entry))
            Error(error) -> history_storage_error(error)
          }
      }
  }
}

fn contribution_archive_decoder() -> decode.Decoder(
  #(String, persistence.HouseholdBudget),
) {
  use period <- decode.field("period", decode.string)
  use people_count <- decode.field("people_count", decode.int)
  use account_balance_cents <- decode.field("account_balance_cents", decode.int)
  use expenses <- decode.field("expenses", decode.list(expense_decoder()))
  decode.success(#(
    period,
    persistence.HouseholdBudget(
      people_count:,
      account_balance_cents:,
      expenses:,
    ),
  ))
}

fn contribution_history_to_json(
  entry: persistence.ContributionHistoryEntry,
) -> json.Json {
  let persistence.ContributionHistoryEntry(
    period:,
    people_count:,
    account_balance_cents:,
    expenses_total_cents:,
    balance_applied_cents:,
    remaining_balance_cents:,
    contribution_total_cents:,
    base_share_cents:,
    residents_paying_one_extra_cent:,
    expenses:,
  ) = entry
  json.object([
    #("period", json.string(period)),
    #("people_count", json.int(people_count)),
    #("account_balance_cents", json.int(account_balance_cents)),
    #("expenses_total_cents", json.int(expenses_total_cents)),
    #("balance_applied_cents", json.int(balance_applied_cents)),
    #("remaining_balance_cents", json.int(remaining_balance_cents)),
    #("contribution_total_cents", json.int(contribution_total_cents)),
    #("base_share_cents", json.int(base_share_cents)),
    #(
      "residents_paying_one_extra_cent",
      json.int(residents_paying_one_extra_cent),
    ),
    #("expenses", json.array(from: expenses, of: expense_to_json)),
  ])
}

fn load_budget(database: pog.Connection) -> wisp.Response {
  case persistence.load(database) {
    Ok(budget) -> respond_json(200, budget_to_json(budget))
    Error(_) -> json_error(500, "The household budget could not be loaded.")
  }
}

fn save_budget(
  request: wisp.Request,
  database: pog.Connection,
) -> wisp.Response {
  case json_request_body(request) {
    Error(response) -> response
    Ok(body) ->
      case json.parse(body, household_budget_decoder()) {
        Error(_) -> json_error(400, "Invalid household budget request body.")
        Ok(budget) ->
          case persistence.save(database, budget) {
            Ok(Nil) -> respond_json(200, budget_to_json(budget))
            Error(error) -> storage_error(error)
          }
      }
  }
}

fn json_request_body(request: wisp.Request) -> Result(String, wisp.Response) {
  case request.get_header(request, "content-type") {
    Ok("application/json") | Ok("application/json;" <> _) -> {
      let request = wisp.set_max_body_size(request, 65_536)
      case wisp.read_body_bits(request) {
        Error(Nil) -> Error(json_error(413, "Request body is too large."))
        Ok(body) ->
          case bit_array.to_string(body) {
            Ok(body) -> Ok(body)
            Error(_) ->
              Error(json_error(400, "Request body is not valid UTF-8."))
          }
      }
    }
    _ -> Error(json_error(415, "Content-Type must be application/json."))
  }
}

fn household_budget_decoder() -> decode.Decoder(persistence.HouseholdBudget) {
  use people_count <- decode.field("people_count", decode.int)
  use account_balance_cents <- decode.field("account_balance_cents", decode.int)
  use expenses <- decode.field("expenses", decode.list(expense_decoder()))
  decode.success(persistence.HouseholdBudget(
    people_count:,
    account_balance_cents:,
    expenses:,
  ))
}

fn expense_decoder() -> decode.Decoder(persistence.ExpenseLine) {
  use label <- decode.field("label", decode.string)
  use amount_cents <- decode.field("amount_cents", decode.int)
  decode.success(persistence.ExpenseLine(label:, amount_cents:))
}

fn budget_to_json(budget: persistence.HouseholdBudget) -> json.Json {
  let persistence.HouseholdBudget(
    people_count:,
    account_balance_cents:,
    expenses:,
  ) = budget
  json.object([
    #("people_count", json.int(people_count)),
    #("account_balance_cents", json.int(account_balance_cents)),
    #("expenses", json.array(from: expenses, of: expense_to_json)),
  ])
}

fn expense_to_json(expense: persistence.ExpenseLine) -> json.Json {
  let persistence.ExpenseLine(label:, amount_cents:) = expense
  json.object([
    #("label", json.string(label)),
    #("amount_cents", json.int(amount_cents)),
  ])
}

fn respond_json(status: Int, body: json.Json) -> wisp.Response {
  wisp.response(status)
  |> wisp.json_body(json.to_string(body))
}

fn json_error(status: Int, message: String) -> wisp.Response {
  respond_json(status, json.object([#("error", json.string(message))]))
}

fn history_storage_error(error: persistence.StorageError) -> wisp.Response {
  case error {
    persistence.InvalidHistoryPeriod ->
      json_error(400, "Period must be a valid month in YYYY-MM format.")
    persistence.InvalidHistoryPeopleCount | persistence.InvalidPeopleCount ->
      json_error(400, "Household size must be at least one person.")
    persistence.NegativeBalance
    | persistence.NegativeExpense
    | persistence.InvalidHistoryCalculation(_) ->
      json_error(400, "The household contribution data is invalid.")
    persistence.DuplicateHistoryPeriod ->
      json_error(
        409,
        "A contribution history entry already exists for this month.",
      )
    persistence.MissingBudget
    | persistence.UnexpectedResultCount
    | persistence.DatabaseError(_) ->
      json_error(500, "The household history could not be saved.")
  }
}

fn storage_error(error: persistence.StorageError) -> wisp.Response {
  case error {
    persistence.InvalidPeopleCount ->
      json_error(400, "Household size must be a non-negative integer.")
    persistence.NegativeBalance ->
      json_error(400, "Account balance must not be negative.")
    persistence.NegativeExpense ->
      json_error(400, "Expense amounts must not be negative.")
    persistence.InvalidHistoryPeriod
    | persistence.InvalidHistoryPeopleCount
    | persistence.DuplicateHistoryPeriod
    | persistence.InvalidHistoryCalculation(_)
    | persistence.MissingBudget
    | persistence.UnexpectedResultCount
    | persistence.DatabaseError(_) ->
      json_error(500, "The household budget could not be saved.")
  }
}
