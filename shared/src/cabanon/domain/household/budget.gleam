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

pub type ContributionPlan {
  ContributionPlan(
    expenses_total_cents: Int,
    balance_applied_cents: Int,
    remaining_balance_cents: Int,
    contribution_total_cents: Int,
    base_share_cents: Int,
    residents_paying_one_extra_cent: Int,
  )
}

pub type CalculationError {
  NoResidents
  NegativeExpense
  NegativeBalance
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

pub fn plan_contributions(
  expenses: List(Expense),
  available_balance_cents: Int,
  residents: Int,
) -> Result(ContributionPlan, CalculationError) {
  case residents <= 0 {
    True -> Error(NoResidents)
    False ->
      case available_balance_cents < 0 {
        True -> Error(NegativeBalance)
        False ->
          case has_negative_expense(expenses) {
            True -> Error(NegativeExpense)
            False -> {
              let expenses_total_cents = total(expenses)
              let balance_applied_cents = case
                available_balance_cents < expenses_total_cents
              {
                True -> available_balance_cents
                False -> expenses_total_cents
              }
              let contribution_total_cents =
                expenses_total_cents - balance_applied_cents

              Ok(ContributionPlan(
                expenses_total_cents:,
                balance_applied_cents:,
                remaining_balance_cents: available_balance_cents
                  - balance_applied_cents,
                contribution_total_cents:,
                base_share_cents: contribution_total_cents / residents,
                residents_paying_one_extra_cent: contribution_total_cents
                  % residents,
              ))
            }
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
