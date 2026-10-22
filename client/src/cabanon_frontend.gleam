import cabanon/domain/construction/costs as construction_costs
import cabanon/domain/household/budget as household_budget
import cabanon/domain/household/money as household_money
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre
import lustre/attribute.{
  attribute, class, disabled, min, placeholder, step, type_, value,
}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import rsvp

type Section {
  HouseholdSection
  ConstructionSection
}

type Model {
  Model(
    section: Section,
    people: String,
    balance: String,
    expenses: List(ExpenseLine),
    next_id: Int,
    construction_costs: List(construction_costs.ActualCost),
    construction_categories: List(String),
    selected_category: String,
    cost_date: String,
    cost_description: String,
    cost_amount: String,
    cost_form_error: Bool,
    category_form_open: Bool,
    new_category: String,
    construction_loading: Bool,
    cost_saving: Bool,
    category_saving: Bool,
    api_error: String,
    household_ready: Bool,
    household_status: HouseholdStatus,
    household_revision: Int,
    household_request_revision: Option(Int),
    household_save_due: Bool,
  )
}

type ExpenseLine {
  ExpenseLine(id: Int, label: String, amount: String)
}

type HouseholdStatus {
  LoadingBudget
  BudgetUnavailable
  BudgetSaved
  BudgetWaiting
  BudgetSaving
  BudgetInvalid
  BudgetSaveFailed
}

type Message {
  ShowHousehold
  ShowConstruction
  AddExpense
  RemoveExpense(Int)
  ChangePeople(String)
  ChangeBalance(String)
  ChangeLabel(Int, String)
  ChangeAmount(Int, String)
  ChangeCostDate(String)
  ChangeCostDescription(String)
  ChangeCostCategory(String)
  ChangeCostAmount(String)
  AddActualCost
  ShowCategoryForm
  ChangeNewCategory(String)
  SaveCategory
  CancelCategoryForm
  ConstructionLoaded(Result(ConstructionData, rsvp.Error(String)))
  ConstructionCostSaved(
    Result(construction_costs.ActualCost, rsvp.Error(String)),
  )
  CategorySaved(Result(String, rsvp.Error(String)))
  HouseholdLoaded(Result(HouseholdData, rsvp.Error(String)))
  HouseholdSaveReady(Int)
  HouseholdSaved(Int, Result(HouseholdData, rsvp.Error(String)))
}

type ConstructionData {
  ConstructionData(
    categories: List(String),
    costs: List(construction_costs.ActualCost),
  )
}

type HouseholdData {
  HouseholdData(
    people_count: Int,
    account_balance_cents: Int,
    expenses: List(StoredExpense),
  )
}

type StoredExpense {
  StoredExpense(label: String, amount_cents: Int)
}

type CalculationProblem {
  InvalidPeople
  InvalidExpense
  InvalidBalance
}

const construction_api_url = "http://localhost:8080/api/construction"

const household_api_url = "http://localhost:8080/api/household"

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

fn init(_flags: Nil) -> #(Model, Effect(Message)) {
  let model =
    Model(
      section: HouseholdSection,
      people: "",
      balance: "",
      expenses: [ExpenseLine(id: 1, label: "", amount: "")],
      next_id: 2,
      construction_costs: [],
      construction_categories: [],
      selected_category: "",
      cost_date: "",
      cost_description: "",
      cost_amount: "",
      cost_form_error: False,
      category_form_open: False,
      new_category: "",
      construction_loading: True,
      cost_saving: False,
      category_saving: False,
      api_error: "",
      household_ready: False,
      household_status: LoadingBudget,
      household_revision: 0,
      household_request_revision: None,
      household_save_due: False,
    )
  let load_construction =
    rsvp.get(
      construction_api_url,
      rsvp.expect_json(construction_data_decoder(), fn(result) {
        ConstructionLoaded(result)
      }),
    )
  let load_household =
    rsvp.get(
      household_api_url,
      rsvp.expect_json(household_data_decoder(), fn(result) {
        HouseholdLoaded(result)
      }),
    )
  #(model, effect.batch([load_construction, load_household]))
}

fn update(model: Model, message: Message) -> #(Model, Effect(Message)) {
  case message {
    ShowHousehold -> no_effect(Model(..model, section: HouseholdSection))
    ShowConstruction -> no_effect(Model(..model, section: ConstructionSection))
    AddExpense ->
      household_changed(
        Model(
          ..model,
          expenses: list.append(model.expenses, [
            ExpenseLine(id: model.next_id, label: "", amount: ""),
          ]),
          next_id: model.next_id + 1,
        ),
      )
    RemoveExpense(id) ->
      household_changed(
        Model(
          ..model,
          expenses: list.filter(model.expenses, fn(expense) { expense.id != id }),
        ),
      )
    ChangePeople(people) -> household_changed(Model(..model, people: people))
    ChangeBalance(balance) ->
      household_changed(Model(..model, balance: balance))
    ChangeLabel(id, label) ->
      household_changed(
        Model(
          ..model,
          expenses: update_expense(model.expenses, id, fn(expense) {
            ExpenseLine(..expense, label: label)
          }),
        ),
      )
    ChangeAmount(id, amount) ->
      household_changed(
        Model(
          ..model,
          expenses: update_expense(model.expenses, id, fn(expense) {
            ExpenseLine(..expense, amount: amount)
          }),
        ),
      )
    ChangeCostDate(date) ->
      no_effect(Model(..model, cost_date: date, cost_form_error: False))
    ChangeCostDescription(description) ->
      no_effect(
        Model(..model, cost_description: description, cost_form_error: False),
      )
    ChangeCostCategory(category) ->
      no_effect(
        Model(..model, selected_category: category, cost_form_error: False),
      )
    ChangeCostAmount(amount) ->
      no_effect(Model(..model, cost_amount: amount, cost_form_error: False))
    AddActualCost -> add_actual_cost(model)
    ShowCategoryForm -> no_effect(Model(..model, category_form_open: True))
    ChangeNewCategory(category) ->
      no_effect(Model(..model, new_category: category))
    SaveCategory -> save_category(model)
    CancelCategoryForm ->
      no_effect(Model(..model, category_form_open: False, new_category: ""))
    ConstructionLoaded(Ok(data)) -> {
      let ConstructionData(categories:, costs:) = data
      let selected_category = case
        category_exists(categories, model.selected_category)
      {
        True -> model.selected_category
        False -> first_category(categories)
      }
      no_effect(
        Model(
          ..model,
          construction_categories: categories,
          construction_costs: costs,
          selected_category:,
          construction_loading: False,
          api_error: "",
        ),
      )
    }
    ConstructionLoaded(Error(_)) ->
      no_effect(
        Model(
          ..model,
          construction_loading: False,
          api_error: "Construction data could not be loaded. Check that the server and PostgreSQL are running, then reload.",
        ),
      )
    ConstructionCostSaved(Ok(cost)) ->
      no_effect(
        Model(
          ..model,
          construction_costs: list.append(model.construction_costs, [cost]),
          cost_description: "",
          cost_amount: "",
          cost_form_error: False,
          cost_saving: False,
          api_error: "",
        ),
      )
    ConstructionCostSaved(Error(_)) ->
      no_effect(
        Model(
          ..model,
          cost_saving: False,
          api_error: "The cost could not be saved. Your entries are still here; check the server and database, then try again.",
        ),
      )
    CategorySaved(Ok(category)) ->
      no_effect(
        Model(
          ..model,
          construction_categories: list.append(model.construction_categories, [
            category,
          ]),
          selected_category: category,
          category_form_open: False,
          new_category: "",
          category_saving: False,
          api_error: "",
        ),
      )
    CategorySaved(Error(_)) ->
      no_effect(
        Model(
          ..model,
          category_saving: False,
          api_error: "The category could not be saved. Your entry is still here; check the server and database, then try again.",
        ),
      )
    HouseholdLoaded(Ok(data)) -> {
      let HouseholdData(people_count, account_balance_cents, stored_expenses) =
        data
      let expenses = stored_expenses_to_lines(stored_expenses, 1)
      no_effect(
        Model(
          ..model,
          people: display_people_count(people_count),
          balance: display_amount_input(account_balance_cents),
          expenses:,
          next_id: list.length(expenses) + 1,
          household_ready: True,
          household_status: BudgetSaved,
          household_revision: 0,
          household_request_revision: None,
          household_save_due: False,
        ),
      )
    }
    HouseholdLoaded(Error(_)) ->
      no_effect(
        Model(
          ..model,
          household_status: BudgetUnavailable,
          household_ready: False,
        ),
      )
    HouseholdSaveReady(revision) -> household_save_ready(model, revision)
    HouseholdSaved(revision, result) ->
      household_save_completed(model, revision, result)
  }
}

fn no_effect(model: Model) -> #(Model, Effect(Message)) {
  #(model, effect.none())
}

fn household_changed(model: Model) -> #(Model, Effect(Message)) {
  case model.household_ready {
    False -> no_effect(model)
    True -> {
      let revision = model.household_revision + 1
      let model =
        Model(
          ..model,
          household_revision: revision,
          household_status: BudgetWaiting,
        )
      let timer =
        effect.from(fn(dispatch) {
          let _ =
            promise.wait(450)
            |> promise.tap(fn(_) { dispatch(HouseholdSaveReady(revision)) })
          Nil
        })
      #(model, timer)
    }
  }
}

fn household_save_ready(
  model: Model,
  revision: Int,
) -> #(Model, Effect(Message)) {
  case revision == model.household_revision {
    False -> no_effect(model)
    True ->
      case household_data(model) {
        Error(Nil) ->
          no_effect(
            Model(
              ..model,
              household_status: BudgetInvalid,
              household_save_due: False,
            ),
          )
        Ok(_) ->
          case model.household_request_revision {
            Some(_) ->
              no_effect(
                Model(
                  ..model,
                  household_status: BudgetWaiting,
                  household_save_due: True,
                ),
              )
            None -> begin_household_save(model, revision)
          }
      }
  }
}

fn begin_household_save(
  model: Model,
  revision: Int,
) -> #(Model, Effect(Message)) {
  case household_data(model) {
    Error(Nil) ->
      no_effect(
        Model(
          ..model,
          household_status: BudgetInvalid,
          household_save_due: False,
        ),
      )
    Ok(data) -> {
      let save =
        rsvp.put(
          household_api_url,
          household_data_to_json(data),
          rsvp.expect_json(household_data_decoder(), fn(result) {
            HouseholdSaved(revision, result)
          }),
        )
      let model =
        Model(
          ..model,
          household_status: BudgetSaving,
          household_request_revision: Some(revision),
          household_save_due: False,
        )
      #(model, save)
    }
  }
}

fn household_save_completed(
  model: Model,
  revision: Int,
  result: Result(HouseholdData, rsvp.Error(String)),
) -> #(Model, Effect(Message)) {
  case model.household_request_revision == Some(revision) {
    False -> no_effect(model)
    True -> {
      let model = Model(..model, household_request_revision: None)
      case result {
        Ok(_) ->
          case model.household_revision == revision {
            True ->
              no_effect(
                Model(
                  ..model,
                  household_status: BudgetSaved,
                  household_save_due: False,
                ),
              )
            False ->
              case model.household_save_due {
                True ->
                  begin_household_save(
                    Model(..model, household_save_due: False),
                    model.household_revision,
                  )
                False -> no_effect(model)
              }
          }
        Error(_) ->
          case model.household_revision == revision {
            True ->
              no_effect(
                Model(
                  ..model,
                  household_status: BudgetSaveFailed,
                  household_save_due: False,
                ),
              )
            False ->
              case model.household_save_due {
                True ->
                  begin_household_save(
                    Model(..model, household_save_due: False),
                    model.household_revision,
                  )
                False -> no_effect(model)
              }
          }
      }
    }
  }
}

fn household_data(model: Model) -> Result(HouseholdData, Nil) {
  let people_count = case string.trim(model.people) {
    "" -> Ok(0)
    input ->
      case int.parse(input) {
        Ok(count) if count >= 0 -> Ok(count)
        _ -> Error(Nil)
      }
  }
  case people_count {
    Error(Nil) -> Error(Nil)
    Ok(people_count) ->
      case amount_cents(model.balance) {
        Error(Nil) -> Error(Nil)
        Ok(account_balance_cents) ->
          case stored_expenses_from_lines(model.expenses) {
            Error(Nil) -> Error(Nil)
            Ok(expenses) ->
              Ok(HouseholdData(people_count:, account_balance_cents:, expenses:))
          }
      }
  }
}

fn stored_expenses_from_lines(
  lines: List(ExpenseLine),
) -> Result(List(StoredExpense), Nil) {
  case lines {
    [] -> Ok([])
    [ExpenseLine(_, label, amount), ..rest] ->
      case amount_cents(amount) {
        Error(Nil) -> Error(Nil)
        Ok(amount_cents) ->
          case stored_expenses_from_lines(rest) {
            Error(Nil) -> Error(Nil)
            Ok(stored_rest) ->
              Ok([StoredExpense(label, amount_cents), ..stored_rest])
          }
      }
  }
}

fn household_data_decoder() -> decode.Decoder(HouseholdData) {
  use people_count <- decode.field("people_count", decode.int)
  use account_balance_cents <- decode.field("account_balance_cents", decode.int)
  use expenses <- decode.field(
    "expenses",
    decode.list(stored_expense_decoder()),
  )
  decode.success(HouseholdData(people_count:, account_balance_cents:, expenses:))
}

fn stored_expense_decoder() -> decode.Decoder(StoredExpense) {
  use label <- decode.field("label", decode.string)
  use amount_cents <- decode.field("amount_cents", decode.int)
  decode.success(StoredExpense(label:, amount_cents:))
}

fn household_data_to_json(data: HouseholdData) -> json.Json {
  let HouseholdData(people_count, account_balance_cents, expenses) = data
  let expenses =
    list.map(expenses, fn(expense) {
      let StoredExpense(label:, amount_cents:) = expense
      json.object([
        #("label", json.string(label)),
        #("amount_cents", json.int(amount_cents)),
      ])
    })
  json.object([
    #("people_count", json.int(people_count)),
    #("account_balance_cents", json.int(account_balance_cents)),
    #("expenses", json.array(from: expenses, of: fn(value) { value })),
  ])
}

fn stored_expenses_to_lines(
  expenses: List(StoredExpense),
  next_id: Int,
) -> List(ExpenseLine) {
  case expenses {
    [] -> []
    [StoredExpense(label, amount_cents), ..rest] -> [
      ExpenseLine(next_id, label, display_amount_input(amount_cents)),
      ..stored_expenses_to_lines(rest, next_id + 1)
    ]
  }
}

fn display_people_count(people_count: Int) -> String {
  case people_count {
    0 -> ""
    count -> int.to_string(count)
  }
}

fn display_amount_input(amount_cents: Int) -> String {
  case amount_cents {
    0 -> ""
    _ -> {
      let fractional = case amount_cents % 100 < 10 {
        True -> "0" <> int.to_string(amount_cents % 100)
        False -> int.to_string(amount_cents % 100)
      }
      int.to_string(amount_cents / 100) <> "." <> fractional
    }
  }
}

fn household_status_note(status: HouseholdStatus) -> String {
  case status {
    LoadingBudget -> "Loading saved household budget..."
    BudgetUnavailable ->
      "Saved data could not be loaded. Check the server and database, then reload."
    BudgetSaved -> "All household changes are saved."
    BudgetWaiting -> "Saving changes automatically..."
    BudgetSaving -> "Saving changes..."
    BudgetInvalid -> "Fix invalid amounts to save your changes."
    BudgetSaveFailed ->
      "Could not save changes. They remain on screen; check the server and try again."
  }
}

fn add_actual_cost(model: Model) -> #(Model, Effect(Message)) {
  case model.cost_saving || model.construction_loading {
    True -> no_effect(model)
    False ->
      case cost_amount_cents(model.cost_amount) {
        Error(Nil) -> no_effect(Model(..model, cost_form_error: True))
        Ok(amount_cents) -> {
          let cost =
            construction_costs.ActualCost(
              incurred_on: string.trim(model.cost_date),
              description: string.trim(model.cost_description),
              category: string.trim(model.selected_category),
              amount_cents: amount_cents,
            )
          case construction_costs.summarise_actual_costs([cost]) {
            Error(_) -> no_effect(Model(..model, cost_form_error: True))
            Ok(_) -> {
              let construction_costs.ActualCost(
                incurred_on:,
                description:,
                category:,
                amount_cents:,
              ) = cost
              let body =
                json.object([
                  #("incurred_on", json.string(incurred_on)),
                  #("description", json.string(description)),
                  #("category", json.string(category)),
                  #("amount_cents", json.int(amount_cents)),
                ])
              let save_cost =
                rsvp.post(
                  construction_api_url <> "/costs",
                  body,
                  rsvp.expect_json(actual_cost_decoder(), fn(result) {
                    ConstructionCostSaved(result)
                  }),
                )
              #(Model(..model, cost_saving: True, api_error: ""), save_cost)
            }
          }
        }
      }
  }
}

fn save_category(model: Model) -> #(Model, Effect(Message)) {
  let category = string.trim(model.new_category)
  case
    model.category_saving
    || model.construction_loading
    || category == ""
    || category_exists(model.construction_categories, category)
  {
    True -> no_effect(model)
    False -> {
      let save_category =
        rsvp.post(
          construction_api_url <> "/categories",
          json.object([#("name", json.string(category))]),
          rsvp.expect_json(category_decoder(), fn(result) {
            CategorySaved(result)
          }),
        )
      #(Model(..model, category_saving: True, api_error: ""), save_category)
    }
  }
}

fn construction_data_decoder() -> decode.Decoder(ConstructionData) {
  use categories <- decode.field("categories", decode.list(decode.string))
  use costs <- decode.field("costs", decode.list(actual_cost_decoder()))
  decode.success(ConstructionData(categories:, costs:))
}

fn actual_cost_decoder() -> decode.Decoder(construction_costs.ActualCost) {
  use incurred_on <- decode.field("incurred_on", decode.string)
  use description <- decode.field("description", decode.string)
  use category <- decode.field("category", decode.string)
  use amount_cents <- decode.field("amount_cents", decode.int)
  decode.success(construction_costs.ActualCost(
    incurred_on:,
    description:,
    category:,
    amount_cents:,
  ))
}

fn category_decoder() -> decode.Decoder(String) {
  use name <- decode.field("name", decode.string)
  decode.success(name)
}

fn first_category(categories: List(String)) -> String {
  case categories {
    [] -> ""
    [category, ..] -> category
  }
}

fn category_exists(categories: List(String), category: String) -> Bool {
  case categories {
    [] -> False
    [candidate, ..rest] ->
      candidate == category || category_exists(rest, category)
  }
}

fn cost_amount_cents(input: String) -> Result(Int, Nil) {
  case string.trim(input) {
    "" -> Error(Nil)
    amount -> household_money.parse_amount(amount)
  }
}

fn update_expense(
  expenses: List(ExpenseLine),
  id: Int,
  change: fn(ExpenseLine) -> ExpenseLine,
) -> List(ExpenseLine) {
  list.map(expenses, fn(expense) {
    case expense.id == id {
      True -> change(expense)
      False -> expense
    }
  })
}

fn view(model: Model) -> Element(Message) {
  case model.section {
    HouseholdSection -> view_household(model)
    ConstructionSection -> view_construction(model)
  }
}

fn view_household(model: Model) -> Element(Message) {
  let plan = calculate_plan(model)
  let total_value = case total_cents(model) {
    Ok(total) -> format_money(total)
    Error(_) -> "—"
  }
  let #(balance_note, balance_has_error) = balance_summary(model, plan)
  let balance_note_class = case balance_has_error {
    True -> "summary-note summary-note-error"
    False -> "summary-note"
  }
  let balance_is_invalid = case amount_cents(model.balance) {
    Ok(_) -> False
    Error(_) -> True
  }
  let balance_input_class = case balance_is_invalid {
    True -> "text-input balance-input input-invalid"
    False -> "text-input balance-input"
  }
  let balance_aria_invalid = case balance_is_invalid {
    True -> "true"
    False -> "false"
  }
  let #(contribution_value, contribution_note, contribution_has_error) =
    contribution_summary(model, plan)
  let contribution_note_class = case contribution_has_error {
    True -> "summary-note summary-note-error"
    False -> "summary-note"
  }
  let #(share_value, share_note, share_has_error) = share_summary(model, plan)
  let share_note_class = case share_has_error {
    True -> "summary-note summary-note-error"
    False -> "summary-note"
  }
  let household_controls_disabled = model.household_ready == False
  let household_note_class = case model.household_status {
    BudgetUnavailable | BudgetInvalid | BudgetSaveFailed ->
      "privacy-note summary-note-error"
    _ -> "privacy-note"
  }
  let expense_rows = case model.expenses {
    [] -> [
      html.div([class("empty-state")], [
        html.div([class("empty-icon"), attribute("aria-hidden", "true")], [
          html.text("+"),
        ]),
        html.h3([], [html.text("No expense items yet")]),
        html.p([], [html.text("Add an expense to start the calculation.")]),
      ]),
    ]
    expenses ->
      list.map(expenses, fn(expense) {
        view_expense(expense, household_controls_disabled)
      })
  }

  html.main([class("page-shell")], [
    html.header([class("topbar")], [
      html.div([class("brand-mark"), attribute("aria-hidden", "true")], [
        html.text("c"),
      ]),
      html.div([], [
        html.p([class("brand-name")], [html.text("cabanon")]),
        html.p([class("brand-caption")], [html.text("HOME FINANCES")]),
      ]),
    ]),
    view_navigation(model.section),
    html.section([class("hero")], [
      html.p([class("eyebrow")], [html.text("SHARED BUDGET")]),
      html.h1([], [
        html.text("Household expenses, "),
        html.span([class("hero-accent")], [html.text("split with clarity.")]),
      ]),
      html.p([class("hero-copy")], [
        html.text(
          "Add household expenses and see the total and everyone's share.",
        ),
      ]),
    ]),
    html.section([class("overview-grid")], [
      html.div([class("summary-card")], [
        html.p([class("summary-label")], [html.text("TOTAL EXPENSES")]),
        html.p([class("summary-value"), attribute("aria-live", "polite")], [
          html.text(total_value),
        ]),
        html.p([class("summary-note")], [
          html.text("Before using account funds"),
        ]),
      ]),
      html.div([class("summary-card summary-card-accent")], [
        html.label([class("field-label"), attribute("for", "account-balance")], [
          html.text("CURRENT ACCOUNT BALANCE"),
        ]),
        html.div([class("money-field balance-field")], [
          html.input([
            class(balance_input_class),
            attribute("id", "account-balance"),
            type_("text"),
            value(model.balance),
            placeholder("0.00"),
            attribute("inputmode", "decimal"),
            attribute("aria-invalid", balance_aria_invalid),
            attribute("aria-describedby", "account-balance-note"),
            disabled(household_controls_disabled),
            event.on_input(ChangeBalance),
          ]),
          html.span(
            [class("currency-symbol"), attribute("aria-hidden", "true")],
            [
              html.text("€"),
            ],
          ),
        ]),
        html.p(
          [class(balance_note_class), attribute("id", "account-balance-note")],
          [html.text(balance_note)],
        ),
      ]),
      html.div([class("summary-card")], [
        html.p([class("summary-label")], [html.text("CONTRIBUTIONS NEEDED")]),
        html.p([class("summary-value"), attribute("aria-live", "polite")], [
          html.text(contribution_value),
        ]),
        html.p([class(contribution_note_class)], [
          html.text(contribution_note),
        ]),
      ]),
      html.div([class("summary-card")], [
        html.label([class("field-label"), attribute("for", "people-count")], [
          html.text("PEOPLE IN HOUSEHOLD"),
        ]),
        html.input([
          class("people-input"),
          attribute("id", "people-count"),
          type_("number"),
          min("1"),
          step("1"),
          value(model.people),
          placeholder("2"),
          attribute("inputmode", "numeric"),
          disabled(household_controls_disabled),
          event.on_input(ChangePeople),
        ]),
        html.p([class("summary-note")], [html.text("Equal split for everyone")]),
        html.p([class("summary-label share-label")], [
          html.text("SHARE PER PERSON"),
        ]),
        html.p(
          [
            class("summary-value summary-value-small"),
            attribute("aria-live", "polite"),
          ],
          [
            html.text(share_value),
          ],
        ),
        html.p([class(share_note_class)], [html.text(share_note)]),
      ]),
    ]),
    html.section([class("expense-panel")], [
      html.div([class("panel-heading")], [
        html.div([], [
          html.p([class("eyebrow eyebrow-dark")], [html.text("YOUR BUDGET")]),
          html.h2([], [html.text("Expense items")]),
        ]),
        html.p([class("panel-hint")], [
          html.text("Totals and shares update as you type."),
        ]),
      ]),
      html.div([class("expense-list")], expense_rows),
      html.div([class("expense-actions")], [
        html.button(
          [
            class("add-button"),
            type_("button"),
            disabled(household_controls_disabled),
            event.on_click(AddExpense),
          ],
          [
            html.span([class("add-icon"), attribute("aria-hidden", "true")], [
              html.text("+"),
            ]),
            html.text("Add an expense"),
          ],
        ),
        html.p([class(household_note_class), attribute("aria-live", "polite")], [
          html.text(household_status_note(model.household_status)),
        ]),
      ]),
    ]),
    html.footer([class("page-footer")], [
      html.text("A shared budget everyone can understand."),
    ]),
  ])
}

fn view_navigation(section: Section) -> Element(Message) {
  let household_class = case section {
    HouseholdSection -> "section-tab section-tab-active"
    ConstructionSection -> "section-tab"
  }
  let construction_class = case section {
    HouseholdSection -> "section-tab"
    ConstructionSection -> "section-tab section-tab-active"
  }

  html.div(
    [
      class("section-tabs"),
      attribute("role", "group"),
      attribute("aria-label", "Main sections"),
    ],
    [
      html.button(
        [
          class(household_class),
          type_("button"),
          attribute("aria-pressed", case section {
            HouseholdSection -> "true"
            ConstructionSection -> "false"
          }),
          event.on_click(ShowHousehold),
        ],
        [html.text("Household")],
      ),
      html.button(
        [
          class(construction_class),
          type_("button"),
          attribute("aria-pressed", case section {
            HouseholdSection -> "false"
            ConstructionSection -> "true"
          }),
          event.on_click(ShowConstruction),
        ],
        [html.text("Construction")],
      ),
    ],
  )
}

fn view_construction(model: Model) -> Element(Message) {
  let summary =
    construction_costs.summarise_actual_costs(model.construction_costs)
  let total = case summary {
    Ok(construction_costs.ActualCostSummary(total_cents, _)) ->
      format_money(total_cents)
    Error(_) -> "—"
  }
  let category_cards = case summary {
    Ok(construction_costs.ActualCostSummary(_, categories)) ->
      case categories {
        [] -> [
          html.p([class("summary-note")], [
            html.text(case model.construction_loading {
              True -> "Loading category totals..."
              False -> "Category totals will appear after your first entry."
            }),
          ]),
        ]
        categories -> list.map(categories, view_category_total)
      }
    Error(_) -> []
  }
  let sorted_costs =
    list.sort(model.construction_costs, fn(left, right) {
      string.compare(right.incurred_on, left.incurred_on)
    })
  let cost_rows = case sorted_costs {
    [] ->
      case model.construction_loading {
        True -> [
          html.div([class("empty-state")], [
            html.h3([], [html.text("Loading your construction history...")]),
          ]),
        ]
        False -> [
          html.div([class("empty-state")], [
            html.div([class("empty-icon"), attribute("aria-hidden", "true")], [
              html.text("+"),
            ]),
            html.h3([], [html.text("No construction costs yet")]),
            html.p([], [
              html.text(
                "Add your first invoice or purchase to start building the real cost history.",
              ),
            ]),
          ]),
        ]
      }
    costs -> list.map(costs, view_actual_cost)
  }
  let description_class = case
    model.cost_form_error && string.trim(model.cost_description) == ""
  {
    True -> "text-input input-invalid"
    False -> "text-input"
  }
  let date_class = case model.cost_form_error && model.cost_date == "" {
    True -> "text-input input-invalid"
    False -> "text-input"
  }
  let amount_is_invalid = case cost_amount_cents(model.cost_amount) {
    Ok(_) -> False
    Error(_) -> True
  }
  let amount_class = case model.cost_form_error && amount_is_invalid {
    True -> "text-input input-invalid"
    False -> "text-input"
  }
  let cost_error = case model.cost_form_error {
    True ->
      html.p(
        [
          class("field-error form-error"),
          attribute("id", "cost-form-error"),
          attribute("role", "alert"),
        ],
        [
          html.text(
            "Enter a date, a description, and a valid non-negative amount.",
          ),
        ],
      )
    False -> html.text("")
  }
  let category_form = case model.category_form_open {
    True -> view_category_form(model)
    False -> html.text("")
  }
  let api_feedback = case model.api_error {
    "" -> html.text("")
    message ->
      html.p([class("field-error form-error"), attribute("role", "alert")], [
        html.text(message),
      ])
  }
  let entry_count = int.to_string(list.length(model.construction_costs))
  let entry_label = case list.length(model.construction_costs) {
    1 -> "recorded cost"
    _ -> "recorded costs"
  }

  html.main([class("page-shell")], [
    html.header([class("topbar")], [
      html.div([class("brand-mark"), attribute("aria-hidden", "true")], [
        html.text("c"),
      ]),
      html.div([], [
        html.p([class("brand-name")], [html.text("cabanon")]),
        html.p([class("brand-caption")], [html.text("HOME FINANCES")]),
      ]),
    ]),
    view_navigation(model.section),
    html.section([class("hero")], [
      html.p([class("eyebrow")], [html.text("HOUSE PROJECT")]),
      html.h1([], [
        html.text("The real cost of your "),
        html.span([class("hero-accent")], [html.text("home.")]),
      ]),
      html.p([class("hero-copy")], [
        html.text(
          "Keep a clear history of construction, interior, and exterior spending.",
        ),
      ]),
    ]),
    api_feedback,
    html.section([class("construction-overview")], [
      html.div([class("summary-card construction-total")], [
        html.p([class("summary-label")], [html.text("TOTAL REAL COST")]),
        html.p([class("summary-value"), attribute("aria-live", "polite")], [
          html.text(total),
        ]),
        html.p([class("summary-note")], [
          html.text(entry_count <> " " <> entry_label),
        ]),
      ]),
      html.div([class("category-summary")], [
        html.p([class("summary-label")], [html.text("COST BY CATEGORY")]),
        html.div([class("category-total-list")], category_cards),
      ]),
    ]),
    html.section([class("expense-panel construction-panel")], [
      html.div([class("panel-heading")], [
        html.div([], [
          html.p([class("eyebrow eyebrow-dark")], [html.text("ADD TO HISTORY")]),
          html.h2([], [html.text("Record a cost")]),
        ]),
        html.p([class("panel-hint")], [
          html.text("Enter each purchase or invoice once, not each instalment."),
        ]),
      ]),
      html.div([class("construction-form")], [
        html.div([class("field")], [
          html.label([class("field-label"), attribute("for", "cost-date")], [
            html.text("Date"),
          ]),
          html.input([
            class(date_class),
            attribute("id", "cost-date"),
            type_("date"),
            value(model.cost_date),
            attribute("required", "required"),
            attribute(
              "aria-invalid",
              case model.cost_form_error && model.cost_date == "" {
                True -> "true"
                False -> "false"
              },
            ),
            event.on_input(ChangeCostDate),
          ]),
        ]),
        html.div([class("field")], [
          html.label(
            [class("field-label"), attribute("for", "cost-description")],
            [html.text("Description")],
          ),
          html.input([
            class(description_class),
            attribute("id", "cost-description"),
            type_("text"),
            value(model.cost_description),
            placeholder("e.g. Foundation work"),
            attribute("required", "required"),
            attribute(
              "aria-invalid",
              case
                model.cost_form_error
                && string.trim(model.cost_description) == ""
              {
                True -> "true"
                False -> "false"
              },
            ),
            event.on_input(ChangeCostDescription),
          ]),
        ]),
        html.div([class("field")], [
          html.label([class("field-label"), attribute("for", "cost-category")], [
            html.text("Category"),
          ]),
          html.select(
            [
              class("text-input"),
              attribute("id", "cost-category"),
              value(model.selected_category),
              disabled(
                model.construction_loading
                || model.construction_categories == [],
              ),
              event.on_change(ChangeCostCategory),
            ],
            list.map(model.construction_categories, fn(category) {
              html.option([attribute("value", category)], category)
            }),
          ),
        ]),
        html.div([class("field")], [
          html.label([class("field-label"), attribute("for", "cost-amount")], [
            html.text("Amount"),
          ]),
          html.div([class("money-field")], [
            html.input([
              class(amount_class),
              attribute("id", "cost-amount"),
              type_("text"),
              value(model.cost_amount),
              placeholder("0.00"),
              attribute("inputmode", "decimal"),
              attribute("required", "required"),
              attribute(
                "aria-invalid",
                case model.cost_form_error && amount_is_invalid {
                  True -> "true"
                  False -> "false"
                },
              ),
              event.on_input(ChangeCostAmount),
            ]),
            html.span(
              [class("currency-symbol"), attribute("aria-hidden", "true")],
              [
                html.text("€"),
              ],
            ),
          ]),
          html.p([class("field-hint")], [
            html.text("Use a comma or a dot for cents."),
          ]),
        ]),
      ]),
      cost_error,
      html.div([class("expense-actions")], [
        html.div([class("form-actions")], [
          html.button(
            [
              class("add-button"),
              type_("button"),
              disabled(
                model.cost_saving
                || model.construction_loading
                || model.construction_categories == [],
              ),
              event.on_click(AddActualCost),
            ],
            [
              html.span([class("add-icon"), attribute("aria-hidden", "true")], [
                html.text("+"),
              ]),
              html.text(case model.cost_saving {
                True -> "Saving..."
                False -> "Add to history"
              }),
            ],
          ),
          html.button(
            [
              class("text-button"),
              type_("button"),
              disabled(model.construction_loading),
              event.on_click(ShowCategoryForm),
            ],
            [html.text("Manage categories")],
          ),
        ]),
        html.p([class("privacy-note")], [
          html.text(
            "Construction costs and categories are saved to PostgreSQL.",
          ),
        ]),
      ]),
      category_form,
    ]),
    html.section([class("expense-panel history-panel")], [
      html.div([class("panel-heading")], [
        html.div([], [
          html.p([class("eyebrow eyebrow-dark")], [html.text("YOUR RECORDS")]),
          html.h2([], [html.text("Cost history")]),
        ]),
        html.p([class("panel-hint")], [
          html.text(
            "Newest entries appear first. Recorded costs are not deleted.",
          ),
        ]),
      ]),
      html.div([class("cost-history")], cost_rows),
    ]),
    html.footer([class("page-footer")], [
      html.text("A clear picture of what your home really costs."),
    ]),
  ])
}

fn view_category_total(
  total: construction_costs.CategoryTotal,
) -> Element(Message) {
  let construction_costs.CategoryTotal(category, total_cents) = total
  html.div([class("category-total")], [
    html.p([class("category-total-name")], [html.text(category)]),
    html.p([class("category-total-value")], [
      html.text(format_money(total_cents)),
    ]),
  ])
}

fn view_actual_cost(cost: construction_costs.ActualCost) -> Element(Message) {
  let construction_costs.ActualCost(date, description, category, amount_cents) =
    cost
  html.article([class("cost-entry")], [
    html.div([class("cost-entry-main")], [
      html.div([class("cost-entry-meta")], [
        html.span([class("cost-date")], [html.text(date)]),
        html.span([class("category-chip")], [html.text(category)]),
      ]),
      html.h3([], [html.text(description)]),
    ]),
    html.p([class("cost-entry-amount")], [html.text(format_money(amount_cents))]),
  ])
}

fn view_category_form(model: Model) -> Element(Message) {
  let duplicate =
    category_exists(
      model.construction_categories,
      string.trim(model.new_category),
    )
  let feedback = case duplicate {
    True -> "This category already exists."
    False -> "Add a category that fits the way you track your project."
  }
  let feedback_class = case duplicate {
    True -> "field-error"
    False -> "field-hint"
  }

  html.div([class("category-form")], [
    html.div([class("field")], [
      html.label([class("field-label"), attribute("for", "new-category")], [
        html.text("New category"),
      ]),
      html.input([
        class("text-input"),
        attribute("id", "new-category"),
        type_("text"),
        value(model.new_category),
        placeholder("e.g. Landscaping"),
        disabled(model.category_saving),
        event.on_input(ChangeNewCategory),
      ]),
      html.p([class(feedback_class)], [html.text(feedback)]),
    ]),
    html.div([class("form-actions")], [
      html.button(
        [
          class("add-button"),
          type_("button"),
          disabled(model.category_saving || model.construction_loading),
          event.on_click(SaveCategory),
        ],
        [
          html.text(case model.category_saving {
            True -> "Saving..."
            False -> "Save category"
          }),
        ],
      ),
      html.button(
        [
          class("text-button"),
          type_("button"),
          event.on_click(CancelCategoryForm),
        ],
        [html.text("Cancel")],
      ),
    ]),
  ])
}

fn view_expense(
  expense: ExpenseLine,
  controls_disabled: Bool,
) -> Element(Message) {
  let id = int.to_string(expense.id)
  let label_id = "expense-label-" <> id
  let amount_id = "expense-amount-" <> id
  let amount_is_invalid = case amount_cents(expense.amount) {
    Ok(_) -> False
    Error(_) -> True
  }
  let amount_class = case amount_is_invalid {
    True -> "text-input input-invalid"
    False -> "text-input"
  }
  let amount_help_class = case amount_is_invalid {
    True -> "field-error"
    False -> "field-hint"
  }
  let remove_label = case string.trim(expense.label) {
    "" -> "Remove this expense"
    label -> "Remove the expense " <> label
  }
  let amount_help = case amount_is_invalid {
    True -> "Enter a non-negative amount with up to two decimal places."
    False -> "e.g. 850.00"
  }

  html.div([class("expense-row")], [
    html.div([class("field")], [
      html.label([class("field-label"), attribute("for", label_id)], [
        html.text("Expense"),
      ]),
      html.input([
        class("text-input"),
        attribute("id", label_id),
        type_("text"),
        value(expense.label),
        placeholder("e.g. Rent"),
        disabled(controls_disabled),
        event.on_input(fn(label) { ChangeLabel(expense.id, label) }),
      ]),
    ]),
    html.div([class("field")], [
      html.label([class("field-label"), attribute("for", amount_id)], [
        html.text("Amount"),
      ]),
      html.div([class("money-field")], [
        html.input([
          class(amount_class),
          attribute("id", amount_id),
          type_("text"),
          value(expense.amount),
          placeholder("0.00"),
          attribute("inputmode", "decimal"),
          attribute("aria-describedby", amount_id <> "-help"),
          disabled(controls_disabled),
          event.on_input(fn(amount) { ChangeAmount(expense.id, amount) }),
        ]),
        html.span([class("currency-symbol"), attribute("aria-hidden", "true")], [
          html.text("€"),
        ]),
      ]),
      html.p([class(amount_help_class), attribute("id", amount_id <> "-help")], [
        html.text(amount_help),
      ]),
    ]),
    html.button(
      [
        class("remove-button"),
        type_("button"),
        attribute("aria-label", remove_label),
        disabled(controls_disabled),
        event.on_click(RemoveExpense(expense.id)),
      ],
      [html.text("Remove")],
    ),
  ])
}

fn total_cents(model: Model) -> Result(Int, Nil) {
  case parse_expenses(model.expenses) {
    Ok(expenses) -> Ok(household_budget.total(expenses))
    Error(Nil) -> Error(Nil)
  }
}

fn balance_summary(
  model: Model,
  plan: Result(household_budget.ContributionPlan, CalculationProblem),
) -> #(String, Bool) {
  case amount_cents(model.balance) {
    Error(Nil) -> #("Enter a non-negative account balance.", True)
    Ok(_) ->
      case plan {
        Ok(household_budget.ContributionPlan(
          _,
          balance_applied,
          remaining_balance,
          _,
          _,
          _,
        )) ->
          case remaining_balance > 0 {
            True -> #(
              format_money(remaining_balance) <> " remains after expenses.",
              False,
            )
            False ->
              case balance_applied > 0 {
                True -> #(
                  format_money(balance_applied) <> " applied to expenses.",
                  False,
                )
                False -> #("No account balance applied.", False)
              }
          }
        Error(InvalidPeople) -> #(
          "Enter household size to calculate the remaining balance.",
          False,
        )
        Error(InvalidExpense) -> #(
          "Fix expense amounts to calculate the balance.",
          True,
        )
        Error(InvalidBalance) -> #(
          "Enter a non-negative account balance.",
          True,
        )
      }
  }
}

fn contribution_summary(
  model: Model,
  plan: Result(household_budget.ContributionPlan, CalculationProblem),
) -> #(String, String, Bool) {
  case string.trim(model.people) {
    "" -> #("—", "Enter household size to calculate contributions.", False)
    _ ->
      case plan {
        Ok(household_budget.ContributionPlan(_, _, _, contribution_total, _, _)) -> #(
          format_money(contribution_total),
          "After applying the available balance.",
          False,
        )
        Error(InvalidPeople) -> #("—", "Enter at least one person.", True)
        Error(InvalidExpense) -> #("—", "Check invalid expense amounts.", True)
        Error(InvalidBalance) -> #("—", "Check the account balance.", True)
      }
  }
}

fn share_summary(
  model: Model,
  plan: Result(household_budget.ContributionPlan, CalculationProblem),
) -> #(String, String, Bool) {
  case string.trim(model.people) {
    "" -> #("—", "Enter the household size to see each share.", False)
    _ ->
      case plan {
        Ok(household_budget.ContributionPlan(
          _,
          _,
          _,
          _,
          base_share,
          extra_cent_people,
        )) -> {
          let note = case extra_cent_people {
            0 -> "The split is exact to the cent."
            1 -> "1 person will pay €0.01 extra to balance the split."
            count ->
              int.to_string(count)
              <> " people will pay €0.01 extra to balance the split."
          }
          #(format_money(base_share), note, False)
        }
        Error(InvalidPeople) -> #("—", "Enter at least one person.", True)
        Error(InvalidExpense) -> #("—", "Check invalid expense amounts.", True)
        Error(InvalidBalance) -> #("—", "Check the account balance.", True)
      }
  }
}

fn calculate_plan(
  model: Model,
) -> Result(household_budget.ContributionPlan, CalculationProblem) {
  case int.parse(model.people) {
    Error(_) -> Error(InvalidPeople)
    Ok(people) ->
      case people <= 0 {
        True -> Error(InvalidPeople)
        False ->
          case amount_cents(model.balance) {
            Error(Nil) -> Error(InvalidBalance)
            Ok(balance) ->
              case parse_expenses(model.expenses) {
                Error(Nil) -> Error(InvalidExpense)
                Ok(expenses) ->
                  case
                    household_budget.plan_contributions(
                      expenses,
                      balance,
                      people,
                    )
                  {
                    Ok(plan) -> Ok(plan)
                    Error(household_budget.NoResidents) -> Error(InvalidPeople)
                    Error(household_budget.NegativeExpense) ->
                      Error(InvalidExpense)
                    Error(household_budget.NegativeBalance) ->
                      Error(InvalidBalance)
                  }
              }
          }
      }
  }
}

fn parse_expenses(
  expenses: List(ExpenseLine),
) -> Result(List(household_budget.Expense), Nil) {
  case expenses {
    [] -> Ok([])
    [expense, ..rest] ->
      case amount_cents(expense.amount) {
        Error(Nil) -> Error(Nil)
        Ok(amount) ->
          case parse_expenses(rest) {
            Error(Nil) -> Error(Nil)
            Ok(parsed_rest) ->
              Ok([household_budget.Expense(amount), ..parsed_rest])
          }
      }
  }
}

fn amount_cents(input: String) -> Result(Int, Nil) {
  case string.trim(input) {
    "" -> Ok(0)
    amount -> household_money.parse_amount(amount)
  }
}

fn format_money(cents: Int) -> String {
  let fractional = case cents % 100 < 10 {
    True -> "0" <> int.to_string(cents % 100)
    False -> int.to_string(cents % 100)
  }

  int.to_string(cents / 100) <> "." <> fractional <> " €"
}
