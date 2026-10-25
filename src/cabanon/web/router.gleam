import cabanon/web/api_response
import cabanon/web/construction_api
import cabanon/web/household_api
import gleam/http
import gleam/http/request as http_request
import gleam/option.{type Option, None, Some}
import pog
import wisp

const development_origin = "http://localhost:1234"

pub fn handle_request(request: wisp.Request) -> wisp.Response {
  handle_request_with_database_and_origin(request, None, development_origin)
}

pub fn handle_request_with_database(
  request: wisp.Request,
  database: Option(pog.Connection),
) -> wisp.Response {
  handle_request_with_database_and_origin(request, database, development_origin)
}

pub fn handle_request_with_database_and_origin(
  request: wisp.Request,
  database: Option(pog.Connection),
  allowed_origin: String,
) -> wisp.Response {
  handle_request_with_database_and_origin_and_static(
    request,
    database,
    allowed_origin,
    None,
  )
}

pub fn handle_request_with_database_and_origin_and_static(
  request: wisp.Request,
  database: Option(pog.Connection),
  allowed_origin: String,
  frontend_directory: Option(String),
) -> wisp.Response {
  use <- wisp.rescue_crashes
  use request <- wisp.handle_head(request)

  case unsafe_request_has_allowed_origin(request, allowed_origin) {
    False -> forbidden()
    True ->
      case wisp.path_segments(request) {
        ["healthz"] -> healthz(request)
        ["healthz", ..] -> wisp.not_found()
        ["readyz"] -> readyz(request, database)
        ["readyz", ..] -> wisp.not_found()
        ["version.json"] ->
          serve_version(request, frontend_directory, allowed_origin)
        ["api", "household", "history"] ->
          case database {
            Some(database) ->
              household_api.handle_history(request, database, allowed_origin)
            None -> household_api.unavailable(request, allowed_origin)
          }
        ["api", "household"] ->
          case database {
            Some(database) ->
              household_api.handle(request, database, allowed_origin)
            None -> household_api.unavailable(request, allowed_origin)
          }
        ["api", "construction"]
        | ["api", "construction", "categories"]
        | ["api", "construction", "costs"]
        | ["api", "construction", "costs", _]
        | ["api", "construction", "costs", _, "corrections"] ->
          case database {
            Some(database) ->
              construction_api.handle(request, database, allowed_origin)
            None -> construction_api.unavailable(request, allowed_origin)
          }
        ["api", ..] -> wisp.not_found()
        _ -> serve_frontend(request, frontend_directory)
      }
  }
}

fn serve_frontend(
  request: wisp.Request,
  frontend_directory: Option(String),
) -> wisp.Response {
  case frontend_directory {
    None -> wisp.not_found()
    Some(directory) ->
      case wisp.path_segments(request) {
        [] -> serve_frontend_index(request, directory)
        _ ->
          wisp.serve_static(request, under: "/", from: directory, next: fn() {
            wisp.not_found()
          })
      }
  }
}

fn serve_version(
  request: wisp.Request,
  frontend_directory: Option(String),
  allowed_origin: String,
) -> wisp.Response {
  let response = case frontend_directory {
    None -> wisp.not_found()
    Some(directory) ->
      wisp.serve_static(request, under: "/", from: directory, next: fn() {
        wisp.not_found()
      })
  }

  api_response.with_headers(response, request, allowed_origin)
}

fn serve_frontend_index(
  request: wisp.Request,
  frontend_directory: String,
) -> wisp.Response {
  let index_request = http_request.Request(..request, path: "/index.html")
  wisp.serve_static(
    index_request,
    under: "/",
    from: frontend_directory,
    next: fn() { wisp.not_found() },
  )
}

pub fn database_ready(database: pog.Connection) -> Bool {
  pog.query("SELECT 1")
  |> pog.timeout(1000)
  |> pog.execute(on: database)
  |> is_ok
}

fn healthz(request: wisp.Request) -> wisp.Response {
  use <- wisp.require_method(request, http.Get)

  wisp.ok()
  |> wisp.html_body("ok")
}

fn readyz(
  request: wisp.Request,
  database: Option(pog.Connection),
) -> wisp.Response {
  use <- wisp.require_method(request, http.Get)

  case database {
    Some(database) ->
      case database_ready(database) {
        True ->
          wisp.ok()
          |> wisp.html_body("ready")
        False ->
          wisp.response(503)
          |> wisp.html_body("database unavailable")
      }
    None ->
      wisp.response(503)
      |> wisp.html_body("database unavailable")
  }
}

fn unsafe_request_has_allowed_origin(
  request: wisp.Request,
  allowed_origin: String,
) -> Bool {
  case request.method {
    http.Post | http.Put | http.Patch | http.Delete ->
      case http_request.get_header(request, "origin") {
        Ok(origin) -> origin == allowed_origin
        Error(_) -> False
      }
    _ -> True
  }
}

fn forbidden() -> wisp.Response {
  wisp.response(403)
  |> wisp.html_body("Forbidden")
}

fn is_ok(result: Result(a, b)) -> Bool {
  case result {
    Ok(_) -> True
    Error(_) -> False
  }
}
