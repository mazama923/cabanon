import cabanon/domain/construction/budget as construction_budget
import cabanon/domain/household/budget as household_budget
import cabanon/web/router
import gleam/http
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import wisp/simulate

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn health_endpoint_returns_ok_test() {
  let response =
    router.handle_request(simulate.browser_request(http.Get, "/healthz"))

  response.status
  |> should.equal(200)
  simulate.read_body(response)
  |> should.equal("ok")
}

pub fn household_split_preserves_every_cent_test() {
  let result =
    household_budget.split(
      [
        household_budget.Expense(1001),
        household_budget.Expense(2002),
      ],
      2,
    )

  result
  |> should.equal(Ok(household_budget.HouseholdShare(3003, 1501, 1)))
}

pub fn household_split_rejects_an_empty_household_test() {
  household_budget.split([], 0)
  |> should.equal(Error(household_budget.NoResidents))
}

pub fn construction_summary_keeps_actual_and_forecast_costs_distinct_test() {
  let summary =
    construction_budget.summarise([
      construction_budget.CostLine(10_000, Some(12_500)),
      construction_budget.CostLine(20_000, None),
    ])

  summary
  |> should.equal(
    Ok(construction_budget.ConstructionSummary(30_000, 12_500, 32_500)),
  )
}

pub fn construction_summary_rejects_negative_estimated_cost_test() {
  construction_budget.summarise([construction_budget.CostLine(-1, None)])
  |> should.equal(Error(construction_budget.NegativeEstimatedCost))
}

pub fn construction_summary_rejects_negative_actual_cost_test() {
  construction_budget.summarise([
    construction_budget.CostLine(1, Some(-1)),
  ])
  |> should.equal(Error(construction_budget.NegativeActualCost))
}
