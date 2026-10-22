import cabanon/env
import cabanon/web/router
import gleam/erlang/process
import gleam/io
import gleam/option.{type Option, None, Some}
import mist
import pog
import wisp/wisp_mist

pub fn main() -> Nil {
  let configuration = case env.load() {
    Ok(configuration) -> configuration
    Error(error) -> panic as env.error_message(error)
  }
  let env.Config(environment:, bind_address:, port:, allowed_origin:) =
    configuration
  let assert Ok(secret_key_base) = env.required("CABANON_SECRET_KEY_BASE")
  let assert Ok(database) = database_connection(environment)
  let frontend_directory = env.frontend_directory(environment)
  let handler = fn(request) {
    router.handle_request_with_database_and_origin_and_static(
      request,
      database,
      allowed_origin,
      frontend_directory,
    )
  }

  let assert Ok(_) =
    handler
    |> wisp_mist.handler(secret_key_base)
    |> mist.new
    |> mist.bind(bind_address)
    |> mist.port(port)
    |> mist.start

  process.sleep_forever()
}

fn database_connection(
  environment: env.Environment,
) -> Result(Option(pog.Connection), Nil) {
  case env.required("CABANON_DATABASE_URL") {
    Error(Nil) ->
      database_unavailable(
        environment,
        "CABANON_DATABASE_URL is unset; database-backed API requests will be unavailable.",
      )
    Ok(database_url) -> {
      let pool_name = process.new_name("cabanon_database")
      case pog.url_config(pool_name, database_url) {
        Error(Nil) ->
          database_unavailable(
            environment,
            "CABANON_DATABASE_URL is invalid; database-backed API requests will be unavailable.",
          )
        Ok(config) ->
          case pog.start(pog.pool_size(config, 5)) {
            Ok(started) ->
              case router.database_ready(started.data) {
                True -> Ok(Some(started.data))
                False ->
                  database_unavailable(
                    environment,
                    "The PostgreSQL database is unavailable; database-backed API requests will be unavailable.",
                  )
              }
            Error(_) ->
              database_unavailable(
                environment,
                "The PostgreSQL connection pool could not start; database-backed API requests will be unavailable.",
              )
          }
      }
    }
  }
}

fn database_unavailable(
  environment: env.Environment,
  message: String,
) -> Result(Option(pog.Connection), Nil) {
  io.println(message)
  case environment {
    env.Production -> Error(Nil)
    env.Development -> Ok(None)
  }
}
