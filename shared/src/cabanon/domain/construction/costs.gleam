import gleam/list
import gleam/string

pub type ActualCost {
  ActualCost(
    incurred_on: String,
    description: String,
    category: String,
    amount_cents: Int,
  )
}

pub type CategoryTotal {
  CategoryTotal(category: String, total_cents: Int)
}

pub type ActualCostSummary {
  ActualCostSummary(total_cents: Int, by_category: List(CategoryTotal))
}

pub type CalculationError {
  MissingDate
  MissingDescription
  MissingCategory
  NegativeActualCost
}

pub fn summarise_actual_costs(
  costs: List(ActualCost),
) -> Result(ActualCostSummary, CalculationError) {
  case validate(costs) {
    Error(error) -> Error(error)
    Ok(Nil) -> {
      let total_cents = list.fold(costs, 0, fn(total, cost) {
        total + cost.amount_cents
      })
      let by_category =
        unique_categories(costs, [])
        |> list.map(fn(category) {
          CategoryTotal(category, total_for_category(costs, category))
        })

      Ok(ActualCostSummary(total_cents:, by_category:))
    }
  }
}

fn validate(costs: List(ActualCost)) -> Result(Nil, CalculationError) {
  case costs {
    [] -> Ok(Nil)
    [cost, ..rest] ->
      case string.trim(cost.incurred_on) {
        "" -> Error(MissingDate)
        _ ->
          case string.trim(cost.description) {
            "" -> Error(MissingDescription)
            _ ->
              case string.trim(cost.category) {
                "" -> Error(MissingCategory)
                _ ->
                  case cost.amount_cents < 0 {
                    True -> Error(NegativeActualCost)
                    False -> validate(rest)
                  }
              }
          }
      }
  }
}

fn unique_categories(costs: List(ActualCost), seen: List(String)) -> List(String) {
  case costs {
    [] -> list.reverse(seen)
    [cost, ..rest] -> {
      let category = string.trim(cost.category)
      case contains_category(seen, category) {
        True -> unique_categories(rest, seen)
        False -> unique_categories(rest, [category, ..seen])
      }
    }
  }
}

fn contains_category(categories: List(String), category: String) -> Bool {
  case categories {
    [] -> False
    [candidate, ..rest] ->
      candidate == category || contains_category(rest, category)
  }
}

fn total_for_category(costs: List(ActualCost), category: String) -> Int {
  list.fold(costs, 0, fn(total, cost) {
    case string.trim(cost.category) == category {
      True -> total + cost.amount_cents
      False -> total
    }
  })
}
