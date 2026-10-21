import gleam/list
import gleam/option.{type Option, None, Some}

pub type CostLine {
  CostLine(estimated_cents: Int, actual_cents: Option(Int))
}

pub type ConstructionSummary {
  ConstructionSummary(
    estimated_total_cents: Int,
    committed_total_cents: Int,
    forecast_total_cents: Int,
  )
}

pub type CalculationError {
  NegativeEstimatedCost
  NegativeActualCost
}

pub fn summarise(
  lines: List(CostLine),
) -> Result(ConstructionSummary, CalculationError) {
  case validate(lines) {
    Error(error) -> Error(error)
    Ok(Nil) -> Ok(lines |> list.fold(ConstructionSummary(0, 0, 0), add_line))
  }
}

fn validate(lines: List(CostLine)) -> Result(Nil, CalculationError) {
  case lines {
    [] -> Ok(Nil)
    [CostLine(estimated_cents:, actual_cents:), ..rest] ->
      case estimated_cents < 0 {
        True -> Error(NegativeEstimatedCost)
        False ->
          case actual_cents {
            Some(amount) if amount < 0 -> Error(NegativeActualCost)
            _ -> validate(rest)
          }
      }
  }
}

fn add_line(
  summary: ConstructionSummary,
  line: CostLine,
) -> ConstructionSummary {
  let CostLine(estimated_cents:, actual_cents:) = line
  let ConstructionSummary(
    estimated_total_cents:,
    committed_total_cents:,
    forecast_total_cents:,
  ) = summary
  let committed_cents = case actual_cents {
    Some(amount) -> amount
    None -> 0
  }
  let forecast_cents = case actual_cents {
    Some(amount) -> amount
    None -> estimated_cents
  }

  ConstructionSummary(
    estimated_total_cents + estimated_cents,
    committed_total_cents + committed_cents,
    forecast_total_cents + forecast_cents,
  )
}
