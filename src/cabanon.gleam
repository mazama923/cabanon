import cabanon/env
import cabanon/web/router
import gleam/erlang/process
import mist
import wisp/wisp_mist

pub fn main() -> Nil {
  let assert Ok(secret_key_base) = env.required("CABANON_SECRET_KEY_BASE")

  let assert Ok(_) =
    router.handle_request
    |> wisp_mist.handler(secret_key_base)
    |> mist.new
    |> mist.port(8080)
    |> mist.start

  process.sleep_forever()
}
