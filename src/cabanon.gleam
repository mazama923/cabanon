import cabanon/env
import cabanon/web/router
import gleam/erlang/process
import gleam/io
import gleam/option.{type Option, None, Some}
import mist
import pog
import wisp/wisp_mist

pub fn main() -> Nil {
  let assert Ok(secret_key_base) = env.required("CABANON_SECRET_KEY_BASE")
  let database = database_connection()
  let handler = fn(request) {
    router.handle_request_with_database(request, database)
  }

  let assert Ok(_) =
    handler
    |> wisp_mist.handler(secret_key_base)
    |> mist.new
    |> mist.bind("127.0.0.1")
    |> mist.port(8080)
    |> mist.start

  process.sleep_forever()
}

fn database_connection() -> Option(pog.Connection) {
  case env.required("CABANON_DATABASE_URL") {
    Error(Nil) -> {
      io.println(
        "CABANON_DATABASE_URL is unset; construction API requests will be unavailable.",
      )
      None
    }
    Ok(database_url) -> {
      let pool_name = process.new_name("cabanon_database")
      case pog.url_config(pool_name, database_url) {
        Error(Nil) -> {
          io.println(
            "CABANON_DATABASE_URL is invalid; construction API requests will be unavailable.",
          )
          None
        }
        Ok(config) ->
          case pog.start(pog.pool_size(config, 5)) {
            Ok(started) -> Some(started.data)
            Error(_) -> {
              io.println(
                "The PostgreSQL connection pool could not start; construction API requests will be unavailable.",
              )
              None
            }
          }
      }
    }
  }
}
