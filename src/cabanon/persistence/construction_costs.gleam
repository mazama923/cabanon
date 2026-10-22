import cabanon/domain/construction/costs as domain_costs
import gleam/dynamic/decode
import gleam/string
import pog

const default_project_id = "00000000-0000-4000-8000-000000000001"

pub type CostRecord {
  CostRecord(id: String, cost: domain_costs.ActualCost, correction_count: Int)
}

pub type CostCorrection {
  CostCorrection(
    id: String,
    reason: String,
    corrected_at: String,
    previous_cost: domain_costs.ActualCost,
  )
}

pub type StorageError {
  InvalidCategory
  DuplicateCategory
  InvalidActualCost(domain_costs.CalculationError)
  InvalidCorrectionReason
  CategoryNotFound
  CostNotFound
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
) -> Result(List(CostRecord), StorageError) {
  let query =
    pog.query(
      "SELECT cost.id::text, cost.incurred_on::text, cost.description, "
      <> "category.name, cost.amount_cents, "
      <> "(SELECT count(*)::integer FROM construction_cost_corrections "
      <> "WHERE construction_cost_id = cost.id) "
      <> "FROM construction_costs AS cost "
      <> "INNER JOIN construction_categories AS category "
      <> "ON category.id = cost.category_id "
      <> "AND category.project_id = cost.project_id "
      <> "WHERE cost.project_id = $1::uuid "
      <> "ORDER BY cost.incurred_on DESC, cost.created_at DESC, cost.id DESC",
    )
    |> pog.parameter(pog.text(default_project_id))
    |> pog.returning(cost_record_decoder())

  case pog.execute(query, on: database) {
    Ok(returned) -> Ok(returned.rows)
    Error(error) -> Error(DatabaseError(error))
  }
}

pub fn list_cost_corrections(
  database: pog.Connection,
  cost_id: String,
) -> Result(List(CostCorrection), StorageError) {
  let query =
    pog.query(
      "SELECT correction.id::text, correction.reason, "
      <> "correction.corrected_at::text, correction.previous_incurred_on::text, "
      <> "correction.previous_description, category.name, "
      <> "correction.previous_amount_cents "
      <> "FROM construction_cost_corrections AS correction "
      <> "INNER JOIN construction_categories AS category "
      <> "ON category.id = correction.previous_category_id "
      <> "WHERE correction.construction_cost_id::text = $1::text "
      <> "ORDER BY correction.corrected_at DESC, correction.id DESC",
    )
    |> pog.parameter(pog.text(cost_id))
    |> pog.returning(cost_correction_decoder())

  case pog.execute(query, on: database) {
    Ok(returned) -> Ok(returned.rows)
    Error(error) -> Error(DatabaseError(error))
  }
}

pub fn create_actual_cost(
  database: pog.Connection,
  cost: domain_costs.ActualCost,
) -> Result(CostRecord, StorageError) {
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
) -> Result(CostRecord, StorageError) {
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
      <> "RETURNING persisted_cost.id::text, persisted_cost.incurred_on::text, "
      <> "persisted_cost.description, "
      <> "(SELECT category_name.name FROM construction_categories "
      <> "AS category_name WHERE category_name.id = persisted_cost.category_id), "
      <> "persisted_cost.amount_cents, 0::integer",
    )
    |> pog.parameter(pog.text(default_project_id))
    |> pog.parameter(pog.text(category))
    |> pog.parameter(pog.int(amount_cents))
    |> pog.parameter(pog.text(incurred_on))
    |> pog.parameter(pog.text(description))
    |> pog.returning(cost_record_decoder())

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

pub fn correct_actual_cost(
  database: pog.Connection,
  cost_id: String,
  cost: domain_costs.ActualCost,
  reason: String,
) -> Result(CostRecord, StorageError) {
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
  let reason = string.trim(reason)

  case reason == "" {
    True -> Error(InvalidCorrectionReason)
    False ->
      case domain_costs.summarise_actual_costs([cost]) {
        Error(error) -> Error(InvalidActualCost(error))
        Ok(_) -> update_actual_cost(database, cost_id, cost, reason)
      }
  }
}

fn update_actual_cost(
  database: pog.Connection,
  cost_id: String,
  cost: domain_costs.ActualCost,
  reason: String,
) -> Result(CostRecord, StorageError) {
  let domain_costs.ActualCost(
    incurred_on:,
    description:,
    category:,
    amount_cents:,
  ) = cost

  let query =
    pog.query(
      "WITH current_cost AS ("
      <> "SELECT cost.id, cost.category_id, cost.amount_cents, "
      <> "cost.incurred_on, cost.description, "
      <> "(SELECT count(*)::integer FROM construction_cost_corrections "
      <> "WHERE construction_cost_id = cost.id) AS correction_count "
      <> "FROM construction_costs AS cost "
      <> "WHERE cost.project_id = $1::uuid AND cost.id::text = $2::text "
      <> "FOR UPDATE OF cost"
      <> "), new_category AS ("
      <> "SELECT category.id, category.name "
      <> "FROM construction_categories AS category "
      <> "WHERE category.project_id = $1::uuid "
      <> "AND lower(btrim(category.name)) = lower(btrim($3::text))"
      <> "), saved_correction AS ("
      <> "INSERT INTO construction_cost_corrections "
      <> "(construction_cost_id, previous_category_id, previous_amount_cents, "
      <> "previous_incurred_on, previous_description, reason) "
      <> "SELECT current_cost.id, current_cost.category_id, "
      <> "current_cost.amount_cents, current_cost.incurred_on, "
      <> "current_cost.description, $6::text "
      <> "FROM current_cost CROSS JOIN new_category "
      <> "RETURNING construction_cost_id"
      <> "), updated_cost AS ("
      <> "UPDATE construction_costs AS cost "
      <> "SET category_id = new_category.id, amount_cents = $4::bigint, "
      <> "incurred_on = ($5::text)::date, description = $7::text "
      <> "FROM saved_correction "
      <> "JOIN new_category ON true "
      <> "JOIN current_cost ON current_cost.id = saved_correction.construction_cost_id "
      <> "WHERE cost.id = saved_correction.construction_cost_id "
      <> "RETURNING cost.id::text, cost.incurred_on::text, cost.description, "
      <> "new_category.name, cost.amount_cents, current_cost.correction_count + 1"
      <> ") SELECT * FROM updated_cost",
    )
    |> pog.parameter(pog.text(default_project_id))
    |> pog.parameter(pog.text(cost_id))
    |> pog.parameter(pog.text(category))
    |> pog.parameter(pog.int(amount_cents))
    |> pog.parameter(pog.text(incurred_on))
    |> pog.parameter(pog.text(reason))
    |> pog.parameter(pog.text(description))
    |> pog.returning(cost_record_decoder())

  case pog.execute(query, on: database) {
    Error(error) -> Error(DatabaseError(error))
    Ok(returned) ->
      case returned.rows {
        [cost] -> Ok(cost)
        [] -> correction_target_error(database, cost_id, category)
        _ -> Error(UnexpectedResultCount)
      }
  }
}

fn correction_target_error(
  database: pog.Connection,
  cost_id: String,
  category: String,
) -> Result(CostRecord, StorageError) {
  let query =
    pog.query(
      "SELECT EXISTS(SELECT 1 FROM construction_costs "
      <> "WHERE project_id = $1::uuid AND id::text = $2::text), "
      <> "EXISTS(SELECT 1 FROM construction_categories "
      <> "WHERE project_id = $1::uuid "
      <> "AND lower(btrim(name)) = lower(btrim($3::text)))",
    )
    |> pog.parameter(pog.text(default_project_id))
    |> pog.parameter(pog.text(cost_id))
    |> pog.parameter(pog.text(category))
    |> pog.returning(correction_target_decoder())

  case pog.execute(query, on: database) {
    Error(error) -> Error(DatabaseError(error))
    Ok(returned) ->
      case returned.rows {
        [#(False, _)] -> Error(CostNotFound)
        [#(True, False)] -> Error(CategoryNotFound)
        [#(True, True)] -> Error(UnexpectedResultCount)
        _ -> Error(UnexpectedResultCount)
      }
  }
}

fn correction_target_decoder() -> decode.Decoder(#(Bool, Bool)) {
  use cost_exists <- decode.subfield([0], decode.bool)
  use category_exists <- decode.subfield([1], decode.bool)
  decode.success(#(cost_exists, category_exists))
}

fn cost_record_decoder() -> decode.Decoder(CostRecord) {
  use id <- decode.subfield([0], decode.string)
  use incurred_on <- decode.subfield([1], decode.string)
  use description <- decode.subfield([2], decode.string)
  use category <- decode.subfield([3], decode.string)
  use amount_cents <- decode.subfield([4], decode.int)
  use correction_count <- decode.subfield([5], decode.int)
  let cost =
    domain_costs.ActualCost(
      incurred_on:,
      description:,
      category:,
      amount_cents:,
    )
  decode.success(CostRecord(id, cost, correction_count))
}

fn cost_correction_decoder() -> decode.Decoder(CostCorrection) {
  use id <- decode.subfield([0], decode.string)
  use reason <- decode.subfield([1], decode.string)
  use corrected_at <- decode.subfield([2], decode.string)
  use incurred_on <- decode.subfield([3], decode.string)
  use description <- decode.subfield([4], decode.string)
  use category <- decode.subfield([5], decode.string)
  use amount_cents <- decode.subfield([6], decode.int)
  let previous_cost =
    domain_costs.ActualCost(
      incurred_on:,
      description:,
      category:,
      amount_cents:,
    )
  decode.success(CostCorrection(id, reason, corrected_at, previous_cost))
}
