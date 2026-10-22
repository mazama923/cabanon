import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type Environment {
  Development
  Production
}

const production_frontend_directory = "/opt/cabanon/current/frontend"

pub type Config {
  Config(
    environment: Environment,
    bind_address: String,
    port: Int,
    allowed_origin: String,
  )
}

pub type ConfigurationError {
  InvalidEnvironment
  MissingProductionSetting(String)
  InvalidPort
  InvalidAllowedOrigin
}

@external(erlang, "cabanon_env", "required")
pub fn required(name: String) -> Result(String, Nil)

pub fn load() -> Result(Config, ConfigurationError) {
  from_values(
    optional("CABANON_ENV"),
    optional("CABANON_BIND_ADDRESS"),
    optional("CABANON_PORT"),
    optional("CABANON_ALLOWED_ORIGIN"),
  )
}

pub fn from_values(
  environment_value: Option(String),
  bind_address_value: Option(String),
  port_value: Option(String),
  allowed_origin_value: Option(String),
) -> Result(Config, ConfigurationError) {
  case environment_value {
    None | Some("development") ->
      config(
        Development,
        value_or_default(bind_address_value, "127.0.0.1"),
        value_or_default(port_value, "8080"),
        value_or_default(allowed_origin_value, "http://localhost:1234"),
      )
    Some("production") ->
      production_config(bind_address_value, port_value, allowed_origin_value)
    Some(_) -> Error(InvalidEnvironment)
  }
}

pub fn frontend_directory(environment: Environment) -> Option(String) {
  case environment {
    Development -> None
    Production -> Some(production_frontend_directory)
  }
}

pub fn error_message(error: ConfigurationError) -> String {
  case error {
    InvalidEnvironment ->
      "CABANON_ENV must be either development or production."
    MissingProductionSetting(name) ->
      name <> " must be set when CABANON_ENV is production."
    InvalidPort -> "CABANON_PORT must be an integer between 1 and 65535."
    InvalidAllowedOrigin ->
      "CABANON_ALLOWED_ORIGIN must be an http:// or https:// origin."
  }
}

fn production_config(
  bind_address_value: Option(String),
  port_value: Option(String),
  allowed_origin_value: Option(String),
) -> Result(Config, ConfigurationError) {
  use bind_address <- result.try(required_production_setting(
    bind_address_value,
    "CABANON_BIND_ADDRESS",
  ))
  use port_value <- result.try(required_production_setting(
    port_value,
    "CABANON_PORT",
  ))
  use allowed_origin <- result.try(required_production_setting(
    allowed_origin_value,
    "CABANON_ALLOWED_ORIGIN",
  ))
  config(Production, bind_address, port_value, allowed_origin)
}

fn config(
  environment: Environment,
  bind_address: String,
  port_value: String,
  allowed_origin: String,
) -> Result(Config, ConfigurationError) {
  use port <- result.try(parse_port(port_value))
  use allowed_origin <- result.try(validate_allowed_origin(allowed_origin))
  Ok(Config(environment:, bind_address:, port:, allowed_origin:))
}

fn optional(name: String) -> Option(String) {
  case required(name) {
    Ok(value) -> Some(value)
    Error(_) -> None
  }
}

fn value_or_default(value: Option(String), default: String) -> String {
  case value {
    Some(value) -> value
    None -> default
  }
}

fn required_production_setting(
  value: Option(String),
  name: String,
) -> Result(String, ConfigurationError) {
  case value {
    Some(value) ->
      case string.is_empty(string.trim(value)) {
        True -> Error(MissingProductionSetting(name))
        False -> Ok(value)
      }
    None -> Error(MissingProductionSetting(name))
  }
}

fn parse_port(value: String) -> Result(Int, ConfigurationError) {
  case int.parse(value) {
    Ok(port) if port >= 1 && port <= 65_535 -> Ok(port)
    _ -> Error(InvalidPort)
  }
}

fn validate_allowed_origin(
  value: String,
) -> Result(String, ConfigurationError) {
  case
    string.starts_with(value, "http://")
    || string.starts_with(value, "https://")
  {
    True -> Ok(value)
    False -> Error(InvalidAllowedOrigin)
  }
}
