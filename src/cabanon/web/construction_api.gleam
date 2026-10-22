import cabanon/domain/construction/costs as domain_costs
import cabanon/persistence/construction_costs as persistence
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
  let response = case wisp.path_segments(request) {
    ["api", "construction"] -> construction_index(request, database)
    ["api", "construction", "categories"] -> categories(request, database)
    ["api", "construction", "costs"] -> costs(request, database)
    ["api", "construction", "costs", cost_id, "corrections"] ->
      cost_corrections(request, database, cost_id)
    ["api", "construction", "costs", cost_id] ->
      cost_detail(request, database, cost_id)
    _ -> wisp.not_found()
  }

  api_response.with_headers(response, request)
}

pub fn unavailable(request: wisp.Request) -> wisp.Response {
  let response = case request.method {
    http.Options -> wisp.response(204)
    _ -> json_error(503, "The construction database is unavailable.")
  }
  api_response.with_headers(response, request)
}

fn construction_index(
  request: wisp.Request,
  database: pog.Connection,
) -> wisp.Response {
  case request.method {
    http.Options -> wisp.response(204)
    http.Get ->
      case persistence.list_categories(database) {
        Error(_) -> storage_error(InternalDatabaseError)
        Ok(categories) ->
          case persistence.list_actual_costs(database) {
            Error(_) -> storage_error(InternalDatabaseError)
            Ok(costs) ->
              respond_json(
                200,
                json.object([
                  #("categories", json.array(from: categories, of: json.string)),
                  #("costs", json.array(from: costs, of: actual_cost_to_json)),
                ]),
              )
          }
      }
    _ -> wisp.method_not_allowed(allowed: [http.Get, http.Options])
  }
}

fn categories(
  request: wisp.Request,
  database: pog.Connection,
) -> wisp.Response {
  case request.method {
    http.Options -> wisp.response(204)
    http.Get ->
      case persistence.list_categories(database) {
        Ok(categories) ->
          respond_json(
            200,
            json.object([
              #("categories", json.array(from: categories, of: json.string)),
            ]),
          )
        Error(_) -> storage_error(InternalDatabaseError)
      }
    http.Post -> create_category(request, database)
    _ -> wisp.method_not_allowed(allowed: [http.Get, http.Post, http.Options])
  }
}

fn costs(request: wisp.Request, database: pog.Connection) -> wisp.Response {
  case request.method {
    http.Options -> wisp.response(204)
    http.Get ->
      case persistence.list_actual_costs(database) {
        Ok(costs) ->
          respond_json(
            200,
            json.object([
              #("costs", json.array(from: costs, of: actual_cost_to_json)),
            ]),
          )
        Error(_) -> storage_error(InternalDatabaseError)
      }
    http.Post -> create_actual_cost(request, database)
    _ -> wisp.method_not_allowed(allowed: [http.Get, http.Post, http.Options])
  }
}

fn create_category(
  request: wisp.Request,
  database: pog.Connection,
) -> wisp.Response {
  case json_request_body(request) {
    Error(response) -> response
    Ok(body) ->
      case json.parse(body, create_category_decoder()) {
        Error(_) -> json_error(400, "Invalid category request body.")
        Ok(category_request) -> {
          let CreateCategoryRequest(name) = category_request
          case persistence.create_category(database, name) {
            Ok(name) ->
              respond_json(201, json.object([#("name", json.string(name))]))
            Error(error) -> storage_error(storage_error_from_persistence(error))
          }
        }
      }
  }
}

fn create_actual_cost(
  request: wisp.Request,
  database: pog.Connection,
) -> wisp.Response {
  case json_request_body(request) {
    Error(response) -> response
    Ok(body) ->
      case json.parse(body, actual_cost_decoder()) {
        Error(_) -> json_error(400, "Invalid construction cost request body.")
        Ok(cost) ->
          case persistence.create_actual_cost(database, cost) {
            Ok(cost) -> respond_json(201, actual_cost_to_json(cost))
            Error(error) -> storage_error(storage_error_from_persistence(error))
          }
      }
  }
}

fn cost_detail(
  request: wisp.Request,
  database: pog.Connection,
  cost_id: String,
) -> wisp.Response {
  case request.method {
    http.Options -> wisp.response(204)
    http.Put -> correct_actual_cost(request, database, cost_id)
    _ -> wisp.method_not_allowed(allowed: [http.Put, http.Options])
  }
}

fn correct_actual_cost(
  request: wisp.Request,
  database: pog.Connection,
  cost_id: String,
) -> wisp.Response {
  case json_request_body(request) {
    Error(response) -> response
    Ok(body) ->
      case json.parse(body, correction_request_decoder()) {
        Error(_) -> json_error(400, "Invalid cost correction request body.")
        Ok(CorrectionRequest(cost, reason)) ->
          case
            persistence.correct_actual_cost(database, cost_id, cost, reason)
          {
            Ok(cost) -> respond_json(200, actual_cost_to_json(cost))
            Error(error) -> storage_error(storage_error_from_persistence(error))
          }
      }
  }
}

fn cost_corrections(
  request: wisp.Request,
  database: pog.Connection,
  cost_id: String,
) -> wisp.Response {
  case request.method {
    http.Options -> wisp.response(204)
    http.Get ->
      case persistence.list_cost_corrections(database, cost_id) {
        Ok(corrections) ->
          respond_json(
            200,
            json.array(from: corrections, of: cost_correction_to_json),
          )
        Error(error) -> storage_error(storage_error_from_persistence(error))
      }
    _ -> wisp.method_not_allowed(allowed: [http.Get, http.Options])
  }
}

fn json_request_body(request: wisp.Request) -> Result(String, wisp.Response) {
  case request.get_header(request, "content-type") {
    Ok("application/json") | Ok("application/json;" <> _) -> {
      let request = wisp.set_max_body_size(request, 16_384)
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

fn create_category_decoder() -> decode.Decoder(CreateCategoryRequest) {
  use name <- decode.field("name", decode.string)
  decode.success(CreateCategoryRequest(name))
}

fn actual_cost_decoder() -> decode.Decoder(domain_costs.ActualCost) {
  use incurred_on <- decode.field("incurred_on", decode.string)
  use description <- decode.field("description", decode.string)
  use category <- decode.field("category", decode.string)
  use amount_cents <- decode.field("amount_cents", decode.int)
  decode.success(domain_costs.ActualCost(
    incurred_on:,
    description:,
    category:,
    amount_cents:,
  ))
}

fn correction_request_decoder() -> decode.Decoder(CorrectionRequest) {
  use incurred_on <- decode.field("incurred_on", decode.string)
  use description <- decode.field("description", decode.string)
  use category <- decode.field("category", decode.string)
  use amount_cents <- decode.field("amount_cents", decode.int)
  use reason <- decode.field("reason", decode.string)
  let cost =
    domain_costs.ActualCost(
      incurred_on:,
      description:,
      category:,
      amount_cents:,
    )
  decode.success(CorrectionRequest(cost, reason))
}

fn actual_cost_to_json(record: persistence.CostRecord) -> json.Json {
  let persistence.CostRecord(id, cost, correction_count) = record
  let domain_costs.ActualCost(
    incurred_on:,
    description:,
    category:,
    amount_cents:,
  ) = cost
  json.object([
    #("id", json.string(id)),
    #("incurred_on", json.string(incurred_on)),
    #("description", json.string(description)),
    #("category", json.string(category)),
    #("amount_cents", json.int(amount_cents)),
    #("correction_count", json.int(correction_count)),
  ])
}

fn cost_correction_to_json(
  correction: persistence.CostCorrection,
) -> json.Json {
  let persistence.CostCorrection(id, reason, corrected_at, previous_cost) =
    correction
  let domain_costs.ActualCost(
    incurred_on:,
    description:,
    category:,
    amount_cents:,
  ) = previous_cost
  json.object([
    #("id", json.string(id)),
    #("reason", json.string(reason)),
    #("corrected_at", json.string(corrected_at)),
    #(
      "previous_cost",
      json.object([
        #("incurred_on", json.string(incurred_on)),
        #("description", json.string(description)),
        #("category", json.string(category)),
        #("amount_cents", json.int(amount_cents)),
      ]),
    ),
  ])
}

fn json_error(status: Int, message: String) -> wisp.Response {
  respond_json(status, json.object([#("error", json.string(message))]))
}

fn respond_json(status: Int, body: json.Json) -> wisp.Response {
  wisp.response(status)
  |> wisp.json_body(json.to_string(body))
}

fn storage_error_from_persistence(
  error: persistence.StorageError,
) -> StorageProblem {
  case error {
    persistence.InvalidCategory -> InvalidCategory
    persistence.DuplicateCategory -> DuplicateCategory
    persistence.InvalidActualCost(_) -> InvalidActualCost
    persistence.InvalidCorrectionReason -> InvalidCorrectionReason
    persistence.CategoryNotFound -> CategoryNotFound
    persistence.CostNotFound -> CostNotFound
    persistence.UnexpectedResultCount -> InternalDatabaseError
    persistence.DatabaseError(_) -> InternalDatabaseError
  }
}

fn storage_error(problem: StorageProblem) -> wisp.Response {
  case problem {
    InvalidCategory -> json_error(400, "Category name is required.")
    DuplicateCategory -> json_error(409, "This category already exists.")
    InvalidActualCost ->
      json_error(400, "Construction cost fields are invalid.")
    InvalidCorrectionReason ->
      json_error(400, "Enter a reason for correcting this cost.")
    CategoryNotFound -> json_error(422, "Choose an existing category.")
    CostNotFound -> json_error(404, "The construction cost was not found.")
    InternalDatabaseError ->
      json_error(500, "The construction data could not be saved.")
  }
}

type CreateCategoryRequest {
  CreateCategoryRequest(name: String)
}

type CorrectionRequest {
  CorrectionRequest(cost: domain_costs.ActualCost, reason: String)
}

type StorageProblem {
  InvalidCategory
  DuplicateCategory
  InvalidActualCost
  InvalidCorrectionReason
  CategoryNotFound
  CostNotFound
  InternalDatabaseError
}
