import gleam/http
import wisp

pub fn handle_request(request: wisp.Request) -> wisp.Response {
  use <- wisp.rescue_crashes
  use request <- wisp.handle_head(request)

  case wisp.path_segments(request) {
    ["healthz"] -> healthz(request)
    _ -> wisp.not_found()
  }
}

fn healthz(request: wisp.Request) -> wisp.Response {
  use <- wisp.require_method(request, http.Get)

  wisp.ok()
  |> wisp.html_body("ok")
}
