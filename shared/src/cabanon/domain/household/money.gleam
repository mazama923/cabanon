import gleam/int
import gleam/string

pub fn parse_amount(input: String) -> Result(Int, Nil) {
  let normalized =
    input
    |> string.trim
    |> string.replace(each: ",", with: ".")

  case normalized {
    "" -> Error(Nil)
    _ ->
      case string.split(normalized, on: ".") {
        [euros] ->
          case parse_non_negative_integer(euros) {
            Ok(euros) -> Ok(euros * 100)
            Error(Nil) -> Error(Nil)
          }
        [euros, fractional] ->
          case parse_non_negative_integer(euros), parse_fractional_cents(fractional) {
            Ok(euros), Ok(cents) -> Ok(euros * 100 + cents)
            _, _ -> Error(Nil)
          }
        _ -> Error(Nil)
      }
  }
}

fn parse_non_negative_integer(input: String) -> Result(Int, Nil) {
  case input {
    "" -> Ok(0)
    _ ->
      case int.parse(input) {
        Ok(value) if value >= 0 -> Ok(value)
        _ -> Error(Nil)
      }
  }
}

fn parse_fractional_cents(input: String) -> Result(Int, Nil) {
  case string.length(input) {
    0 -> Ok(0)
    1 ->
      case int.parse(input) {
        Ok(value) if value >= 0 -> Ok(value * 10)
        _ -> Error(Nil)
      }
    2 ->
      case int.parse(input) {
        Ok(value) if value >= 0 -> Ok(value)
        _ -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}
