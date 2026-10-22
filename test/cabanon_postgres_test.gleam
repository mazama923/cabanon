import cabanon/domain/construction/costs as domain_costs
import cabanon/env
import cabanon/persistence/construction_costs as persistence
import cabanon/persistence/household_budget as household_persistence
import cabanon/web/router
import gleam/erlang/process
import gleam/http
import gleam/http/request
import gleam/io
import gleam/option.{Some}
import gleeunit/should
import pog
import wisp/simulate

pub fn construction_repository_round_trips_costs_and_categories_test() {
  case env.required("CABANON_TEST_DATABASE_URL") {
    Error(Nil) ->
      io.println(
        "Skipping PostgreSQL integration test: CABANON_TEST_DATABASE_URL is unset.",
      )
    Ok(database_url) ->
      with_database(database_url, fn(database) {
        let result =
          pog.transaction(database, fn(transaction) {
            persistence.list_categories(transaction)
            |> should.equal(Ok(["Construction", "Interior", "Exterior"]))

            persistence.list_actual_costs(transaction)
            |> should.equal(Ok([]))

            persistence.create_category(transaction, "Landscaping")
            |> should.equal(Ok("Landscaping"))

            persistence.create_category(transaction, " landscaping ")
            |> should.equal(Error(persistence.DuplicateCategory))

            let cost =
              domain_costs.ActualCost(
                incurred_on: "2026-06-15",
                description: "Garden paving",
                category: "Landscaping",
                amount_cents: 12_345,
              )

            persistence.create_actual_cost(transaction, cost)
            |> should.equal(Ok(cost))

            persistence.list_actual_costs(transaction)
            |> should.equal(Ok([cost]))

            let invalid_cost = domain_costs.ActualCost(..cost, amount_cents: -1)
            persistence.create_actual_cost(transaction, invalid_cost)
            |> should.equal(
              Error(persistence.InvalidActualCost(
                domain_costs.NegativeActualCost,
              )),
            )

            Error(IntegrationRollback)
          })

        result
        |> should.equal(Error(pog.TransactionRolledBack(IntegrationRollback)))
      })
  }
}

pub fn construction_api_round_trips_categories_and_costs_test() {
  case env.required("CABANON_TEST_DATABASE_URL") {
    Error(Nil) ->
      io.println(
        "Skipping PostgreSQL API test: CABANON_TEST_DATABASE_URL is unset.",
      )
    Ok(database_url) ->
      with_database(database_url, fn(database) {
        let result =
          pog.transaction(database, fn(transaction) {
            let household_initial_response =
              router.handle_request_with_database(
                simulate.request(http.Get, "/api/household"),
                Some(transaction),
              )
            household_initial_response.status |> should.equal(200)
            simulate.read_body(household_initial_response)
            |> should.equal(
              "{\"people_count\":0,\"account_balance_cents\":0,\"expenses\":[]}",
            )

            let household_request =
              simulate.request(http.Put, "/api/household")
              |> simulate.string_body(
                "{\"people_count\":3,\"account_balance_cents\":5500,\"expenses\":[{\"label\":\"Rent\",\"amount_cents\":120000},{\"label\":\"Electricity\",\"amount_cents\":8500}]}",
              )
              |> request.set_header("content-type", "application/json")
            let household_response =
              router.handle_request_with_database(
                household_request,
                Some(transaction),
              )
            household_response.status |> should.equal(200)
            simulate.read_body(household_response)
            |> should.equal(
              "{\"people_count\":3,\"account_balance_cents\":5500,\"expenses\":[{\"label\":\"Rent\",\"amount_cents\":120000},{\"label\":\"Electricity\",\"amount_cents\":8500}]}",
            )

            household_persistence.load(transaction)
            |> should.equal(
              Ok(
                household_persistence.HouseholdBudget(
                  people_count: 3,
                  account_balance_cents: 5500,
                  expenses: [
                    household_persistence.ExpenseLine("Rent", 120_000),
                    household_persistence.ExpenseLine("Electricity", 8500),
                  ],
                ),
              ),
            )

            household_persistence.save(
              transaction,
              household_persistence.HouseholdBudget(
                people_count: 2,
                account_balance_cents: 0,
                expenses: [
                  household_persistence.ExpenseLine("Rent", 120_000),
                ],
              ),
            )
            |> should.equal(Ok(Nil))
            household_persistence.load(transaction)
            |> should.equal(
              Ok(
                household_persistence.HouseholdBudget(
                  people_count: 2,
                  account_balance_cents: 0,
                  expenses: [
                    household_persistence.ExpenseLine("Rent", 120_000),
                  ],
                ),
              ),
            )

            let initial_response =
              router.handle_request_with_database(
                simulate.request(http.Get, "/api/construction"),
                Some(transaction),
              )
            initial_response.status |> should.equal(200)
            simulate.read_body(initial_response)
            |> should.equal(
              "{\"categories\":[\"Construction\",\"Interior\",\"Exterior\"],\"costs\":[]}",
            )

            let category_request =
              simulate.request(http.Post, "/api/construction/categories")
              |> simulate.string_body("{\"name\":\"Landscaping\"}")
              |> request.set_header("content-type", "application/json")
            let category_response =
              router.handle_request_with_database(
                category_request,
                Some(transaction),
              )
            category_response.status |> should.equal(201)
            simulate.read_body(category_response)
            |> should.equal("{\"name\":\"Landscaping\"}")

            let cost_request =
              simulate.request(http.Post, "/api/construction/costs")
              |> simulate.string_body(
                "{\"incurred_on\":\"2026-06-15\",\"description\":\"Garden paving\",\"category\":\"Landscaping\",\"amount_cents\":12345}",
              )
              |> request.set_header("content-type", "application/json")
            let cost_response =
              router.handle_request_with_database(
                cost_request,
                Some(transaction),
              )
            cost_response.status |> should.equal(201)
            simulate.read_body(cost_response)
            |> should.equal(
              "{\"incurred_on\":\"2026-06-15\",\"description\":\"Garden paving\",\"category\":\"Landscaping\",\"amount_cents\":12345}",
            )

            let final_response =
              router.handle_request_with_database(
                simulate.request(http.Get, "/api/construction"),
                Some(transaction),
              )
            final_response.status |> should.equal(200)
            simulate.read_body(final_response)
            |> should.equal(
              "{\"categories\":[\"Construction\",\"Interior\",\"Exterior\",\"Landscaping\"],\"costs\":[{\"incurred_on\":\"2026-06-15\",\"description\":\"Garden paving\",\"category\":\"Landscaping\",\"amount_cents\":12345}]}",
            )

            Error(IntegrationRollback)
          })

        result
        |> should.equal(Error(pog.TransactionRolledBack(IntegrationRollback)))
      })
  }
}

fn with_database(
  database_url: String,
  run_checks: fn(pog.Connection) -> Nil,
) -> Nil {
  let pool_name = process.new_name("cabanon_postgres_test")
  let assert Ok(config) = pog.url_config(pool_name, database_url)
  let assert Ok(started) = pog.start(pog.pool_size(config, 1))
  await_database(started.data, 20)
  |> should.equal(Ok(Nil))
  run_checks(started.data)
}

fn await_database(
  database: pog.Connection,
  attempts: Int,
) -> Result(Nil, persistence.StorageError) {
  case persistence.list_categories(database) {
    Ok(_) -> Ok(Nil)
    Error(persistence.DatabaseError(pog.ConnectionUnavailable))
      if attempts > 0
    -> {
      process.sleep(50)
      await_database(database, attempts - 1)
    }
    Error(error) -> Error(error)
  }
}

type IntegrationRollback {
  IntegrationRollback
}
