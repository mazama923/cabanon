import gleam/http/request
import gleam/http/response
import wisp

pub fn with_headers(
  response: wisp.Response,
  request: wisp.Request,
  allowed_origin: String,
) -> wisp.Response {
  let response =
    response
    |> response.set_header("cache-control", "no-store")
    |> response.set_header("vary", "Origin")
    |> response.set_header(
      "access-control-allow-methods",
      "GET, POST, PUT, OPTIONS",
    )
    |> response.set_header("access-control-allow-headers", "content-type")
    |> response.set_header("access-control-max-age", "600")

  case request.get_header(request, "origin") {
    Ok(origin) if origin == allowed_origin ->
      response
      |> response.set_header("access-control-allow-origin", origin)
    _ -> response
  }
}
