import gleam/list

pub type Expense {
  Expense(amount_cents: Int)
}

pub type HouseholdShare {
  HouseholdShare(
    total_cents: Int,
    base_share_cents: Int,
    residents_paying_one_extra_cent: Int,
  )
}

pub type CalculationError {
  NoResidents
  NegativeExpense
}

pub fn split(
  expenses: List(Expense),
  residents: Int,
) -> Result(HouseholdShare, CalculationError) {
  case residents <= 0 {
    True -> Error(NoResidents)
    False ->
      case has_negative_expense(expenses) {
        True -> Error(NegativeExpense)
        False -> {
          let total_cents = total(expenses)
          Ok(HouseholdShare(
            total_cents:,
            base_share_cents: total_cents / residents,
            residents_paying_one_extra_cent: total_cents % residents,
          ))
        }
      }
  }
}

pub fn total(expenses: List(Expense)) -> Int {
  expenses
  |> list.fold(0, fn(total, expense) { total + expense.amount_cents })
}

fn has_negative_expense(expenses: List(Expense)) -> Bool {
  case expenses {
    [] -> False
    [Expense(amount_cents: amount_cents), ..rest] ->
      amount_cents < 0 || has_negative_expense(rest)
  }
}
