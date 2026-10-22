import cabanon/domain/construction/budget as construction_budget
import cabanon/domain/construction/costs as construction_costs
import cabanon/domain/household/budget as household_budget
import cabanon/domain/household/money as household_money
import cabanon/web/router
import gleam/http
import gleam/http/response as http_response
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

pub fn construction_api_reports_unavailable_without_database_test() {
  let request =
    simulate.request(http.Get, "/api/construction")
    |> simulate.header("origin", "http://localhost:1234")
  let response = router.handle_request(request)

  response.status |> should.equal(503)
  http_response.get_header(response, "access-control-allow-origin")
  |> should.equal(Ok("http://localhost:1234"))
  simulate.read_body(response)
  |> should.equal("{\"error\":\"The construction database is unavailable.\"}")

  let household_response =
    router.handle_request(simulate.request(http.Get, "/api/household"))
  household_response.status |> should.equal(503)
  simulate.read_body(household_response)
  |> should.equal("{\"error\":\"The household database is unavailable.\"}")
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

pub fn household_plan_deducts_available_balance_before_equal_split_test() {
  household_budget.plan_contributions(
    [
      household_budget.Expense(1001),
      household_budget.Expense(2002),
    ],
    1000,
    2,
  )
  |> should.equal(
    Ok(household_budget.ContributionPlan(
      expenses_total_cents: 3003,
      balance_applied_cents: 1000,
      remaining_balance_cents: 0,
      contribution_total_cents: 2003,
      base_share_cents: 1001,
      residents_paying_one_extra_cent: 1,
    )),
  )
}

pub fn household_plan_keeps_surplus_and_never_returns_negative_contributions_test() {
  household_budget.plan_contributions([household_budget.Expense(3003)], 4000, 2)
  |> should.equal(
    Ok(household_budget.ContributionPlan(
      expenses_total_cents: 3003,
      balance_applied_cents: 3003,
      remaining_balance_cents: 997,
      contribution_total_cents: 0,
      base_share_cents: 0,
      residents_paying_one_extra_cent: 0,
    )),
  )
}

pub fn household_plan_rejects_a_negative_account_balance_test() {
  household_budget.plan_contributions([household_budget.Expense(1000)], -1, 2)
  |> should.equal(Error(household_budget.NegativeBalance))
}

pub fn household_plan_rejects_invalid_residents_and_expenses_test() {
  household_budget.plan_contributions([], 0, 0)
  |> should.equal(Error(household_budget.NoResidents))

  household_budget.plan_contributions([household_budget.Expense(-1)], 0, 2)
  |> should.equal(Error(household_budget.NegativeExpense))
}

pub fn household_money_parses_decimal_amounts_as_integer_cents_test() {
  household_money.parse_amount("12.34")
  |> should.equal(Ok(1234))

  household_money.parse_amount("12,3")
  |> should.equal(Ok(1230))

  household_money.parse_amount(",50")
  |> should.equal(Ok(50))
}

pub fn household_money_rejects_negative_and_excess_precision_test() {
  household_money.parse_amount("-1.00")
  |> should.equal(Error(Nil))

  household_money.parse_amount("1.234")
  |> should.equal(Error(Nil))
}

pub fn household_split_rejects_an_empty_household_test() {
  household_budget.split([], 0)
  |> should.equal(Error(household_budget.NoResidents))
}

pub fn construction_actual_costs_are_summarised_by_category_test() {
  construction_costs.summarise_actual_costs([
    construction_costs.ActualCost(
      incurred_on: "2026-04-10",
      description: "Foundation concrete",
      category: "Construction",
      amount_cents: 10_000,
    ),
    construction_costs.ActualCost(
      incurred_on: "2026-05-02",
      description: "Windows",
      category: "Construction",
      amount_cents: 5000,
    ),
    construction_costs.ActualCost(
      incurred_on: "2026-05-12",
      description: "Garden wall",
      category: "Exterior",
      amount_cents: 2500,
    ),
  ])
  |> should.equal(
    Ok(
      construction_costs.ActualCostSummary(total_cents: 17_500, by_category: [
        construction_costs.CategoryTotal("Construction", 15_000),
        construction_costs.CategoryTotal("Exterior", 2500),
      ]),
    ),
  )
}

pub fn construction_actual_costs_require_history_fields_and_non_negative_amounts_test() {
  construction_costs.summarise_actual_costs([
    construction_costs.ActualCost(
      incurred_on: "",
      description: "Foundation concrete",
      category: "Construction",
      amount_cents: 10_000,
    ),
  ])
  |> should.equal(Error(construction_costs.MissingDate))

  construction_costs.summarise_actual_costs([
    construction_costs.ActualCost(
      incurred_on: "2026-04-10",
      description: "Foundation concrete",
      category: "Construction",
      amount_cents: -1,
    ),
  ])
  |> should.equal(Error(construction_costs.NegativeActualCost))
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
