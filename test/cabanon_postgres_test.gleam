import cabanon/domain/construction/costs as domain_costs
import cabanon/env
import cabanon/persistence/construction_costs as persistence
import gleam/erlang/process
import gleam/io
import gleeunit/should
import pog

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
