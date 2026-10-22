import cabanon/web/construction_api
import cabanon/web/household_api
import gleam/http
import gleam/option.{type Option, None, Some}
import pog
import wisp

pub fn handle_request(request: wisp.Request) -> wisp.Response {
  handle_request_with_database(request, None)
}

pub fn handle_request_with_database(
  request: wisp.Request,
  database: Option(pog.Connection),
) -> wisp.Response {
  use <- wisp.rescue_crashes
  use request <- wisp.handle_head(request)

  case wisp.path_segments(request) {
    ["healthz"] -> healthz(request)
    ["api", "household", "history"] ->
      case database {
        Some(database) -> household_api.handle_history(request, database)
        None -> household_api.unavailable(request)
      }
    ["api", "household"] ->
      case database {
        Some(database) -> household_api.handle(request, database)
        None -> household_api.unavailable(request)
      }
    ["api", "construction"]
    | ["api", "construction", "categories"]
    | ["api", "construction", "costs"]
    | ["api", "construction", "costs", _]
    | ["api", "construction", "costs", _, "corrections"] ->
      case database {
        Some(database) -> construction_api.handle(request, database)
        None -> construction_api.unavailable(request)
      }
    _ -> wisp.not_found()
  }
}

fn healthz(request: wisp.Request) -> wisp.Response {
  use <- wisp.require_method(request, http.Get)

  wisp.ok()
  |> wisp.html_body("ok")
}
