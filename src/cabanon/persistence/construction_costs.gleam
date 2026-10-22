import cabanon/domain/construction/costs as domain_costs
import gleam/dynamic/decode
import gleam/string
import pog

const default_project_id = "00000000-0000-4000-8000-000000000001"

pub type StorageError {
  InvalidCategory
  DuplicateCategory
  InvalidActualCost(domain_costs.CalculationError)
  CategoryNotFound
  UnexpectedResultCount
  DatabaseError(pog.QueryError)
}

pub fn list_categories(
  database: pog.Connection,
) -> Result(List(String), StorageError) {
  let query =
    pog.query(
      "SELECT name FROM construction_categories "
      <> "WHERE project_id = $1::uuid "
      <> "ORDER BY sort_order, lower(name)",
    )
    |> pog.parameter(pog.text(default_project_id))
    |> pog.returning(decode.at([0], decode.string))

  case pog.execute(query, on: database) {
    Ok(returned) -> Ok(returned.rows)
    Error(error) -> Error(DatabaseError(error))
  }
}

pub fn create_category(
  database: pog.Connection,
  name: String,
) -> Result(String, StorageError) {
  let name = string.trim(name)
  case name == "" {
    True -> Error(InvalidCategory)
    False -> {
      let query =
        pog.query(
          "INSERT INTO construction_categories (project_id, name, sort_order) "
          <> "SELECT $1::uuid, $2::text, COALESCE(MAX(sort_order), 0) + 10 "
          <> "FROM construction_categories WHERE project_id = $1::uuid "
          <> "ON CONFLICT DO NOTHING RETURNING name",
        )
        |> pog.parameter(pog.text(default_project_id))
        |> pog.parameter(pog.text(name))
        |> pog.returning(decode.at([0], decode.string))

      case pog.execute(query, on: database) {
        Ok(returned) ->
          case returned.rows {
            [category] -> Ok(category)
            [] -> Error(DuplicateCategory)
            _ -> Error(UnexpectedResultCount)
          }
        Error(error) -> Error(DatabaseError(error))
      }
    }
  }
}

pub fn list_actual_costs(
  database: pog.Connection,
) -> Result(List(domain_costs.ActualCost), StorageError) {
  let query =
    pog.query(
      "SELECT cost.incurred_on::text, cost.description, category.name, "
      <> "cost.amount_cents FROM construction_costs AS cost "
      <> "INNER JOIN construction_categories AS category "
      <> "ON category.id = cost.category_id "
      <> "AND category.project_id = cost.project_id "
      <> "WHERE cost.project_id = $1::uuid "
      <> "ORDER BY cost.incurred_on DESC, cost.created_at DESC, cost.id DESC",
    )
    |> pog.parameter(pog.text(default_project_id))
    |> pog.returning(actual_cost_decoder())

  case pog.execute(query, on: database) {
    Ok(returned) -> Ok(returned.rows)
    Error(error) -> Error(DatabaseError(error))
  }
}

pub fn create_actual_cost(
  database: pog.Connection,
  cost: domain_costs.ActualCost,
) -> Result(domain_costs.ActualCost, StorageError) {
  let domain_costs.ActualCost(
    incurred_on:,
    description:,
    category:,
    amount_cents:,
  ) = cost
  let cost =
    domain_costs.ActualCost(
      incurred_on: string.trim(incurred_on),
      description: string.trim(description),
      category: string.trim(category),
      amount_cents:,
    )

  case domain_costs.summarise_actual_costs([cost]) {
    Error(error) -> Error(InvalidActualCost(error))
    Ok(_) -> insert_actual_cost(database, cost)
  }
}

fn insert_actual_cost(
  database: pog.Connection,
  cost: domain_costs.ActualCost,
) -> Result(domain_costs.ActualCost, StorageError) {
  let domain_costs.ActualCost(
    incurred_on:,
    description:,
    category:,
    amount_cents:,
  ) = cost

  let query =
    pog.query(
      "INSERT INTO construction_costs AS persisted_cost "
      <> "(project_id, category_id, amount_cents, incurred_on, description) "
      <> "SELECT $1::uuid, category.id, $3::bigint, ($4::text)::date, $5::text "
      <> "FROM construction_categories AS category "
      <> "WHERE category.project_id = $1::uuid "
      <> "AND lower(btrim(category.name)) = lower(btrim($2::text)) "
      <> "RETURNING incurred_on::text, description, "
      <> "(SELECT category_name.name FROM construction_categories "
      <> "AS category_name WHERE category_name.id = persisted_cost.category_id), "
      <> "amount_cents",
    )
    |> pog.parameter(pog.text(default_project_id))
    |> pog.parameter(pog.text(category))
    |> pog.parameter(pog.int(amount_cents))
    |> pog.parameter(pog.text(incurred_on))
    |> pog.parameter(pog.text(description))
    |> pog.returning(actual_cost_decoder())

  case pog.execute(query, on: database) {
    Ok(returned) ->
      case returned.rows {
        [persisted_cost] -> Ok(persisted_cost)
        [] -> Error(CategoryNotFound)
        _ -> Error(UnexpectedResultCount)
      }
    Error(error) -> Error(DatabaseError(error))
  }
}

fn actual_cost_decoder() -> decode.Decoder(domain_costs.ActualCost) {
  use incurred_on <- decode.subfield([0], decode.string)
  use description <- decode.subfield([1], decode.string)
  use category <- decode.subfield([2], decode.string)
  use amount_cents <- decode.subfield([3], decode.int)
  decode.success(domain_costs.ActualCost(
    incurred_on:,
    description:,
    category:,
    amount_cents:,
  ))
}
