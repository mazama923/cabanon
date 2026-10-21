import cabanon/domain/construction/costs as construction_costs
import cabanon/domain/household/budget as household_budget
import cabanon/domain/household/money as household_money
import gleam/int
import gleam/list
import gleam/string
import lustre
import lustre/attribute.{attribute, class, min, placeholder, step, type_, value}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

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
  )
}

type ExpenseLine {
  ExpenseLine(id: Int, label: String, amount: String)
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
}

type CalculationProblem {
  InvalidPeople
  InvalidExpense
  InvalidBalance
}

pub fn main() {
  let app = lustre.simple(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

fn init(_flags: Nil) -> Model {
  Model(
    section: HouseholdSection,
    people: "",
    balance: "",
    expenses: [ExpenseLine(id: 1, label: "", amount: "")],
    next_id: 2,
    construction_costs: [],
    construction_categories: ["Construction", "Interior", "Exterior"],
    selected_category: "Construction",
    cost_date: "",
    cost_description: "",
    cost_amount: "",
    cost_form_error: False,
    category_form_open: False,
    new_category: "",
  )
}

fn update(model: Model, message: Message) -> Model {
  case message {
    ShowHousehold -> Model(..model, section: HouseholdSection)
    ShowConstruction -> Model(..model, section: ConstructionSection)
    AddExpense ->
      Model(
        ..model,
        expenses: list.append(model.expenses, [
          ExpenseLine(id: model.next_id, label: "", amount: ""),
        ]),
        next_id: model.next_id + 1,
      )
    RemoveExpense(id) ->
      Model(
        ..model,
        expenses: list.filter(model.expenses, fn(expense) { expense.id != id }),
      )
    ChangePeople(people) -> Model(..model, people: people)
    ChangeBalance(balance) -> Model(..model, balance: balance)
    ChangeLabel(id, label) ->
      Model(
        ..model,
        expenses: update_expense(model.expenses, id, fn(expense) {
          ExpenseLine(..expense, label: label)
        }),
      )
    ChangeAmount(id, amount) ->
      Model(
        ..model,
        expenses: update_expense(model.expenses, id, fn(expense) {
          ExpenseLine(..expense, amount: amount)
        }),
      )
    ChangeCostDate(date) ->
      Model(..model, cost_date: date, cost_form_error: False)
    ChangeCostDescription(description) ->
      Model(..model, cost_description: description, cost_form_error: False)
    ChangeCostCategory(category) ->
      Model(..model, selected_category: category, cost_form_error: False)
    ChangeCostAmount(amount) ->
      Model(..model, cost_amount: amount, cost_form_error: False)
    AddActualCost -> add_actual_cost(model)
    ShowCategoryForm -> Model(..model, category_form_open: True)
    ChangeNewCategory(category) -> Model(..model, new_category: category)
    SaveCategory -> save_category(model)
    CancelCategoryForm ->
      Model(..model, category_form_open: False, new_category: "")
  }
}

fn add_actual_cost(model: Model) -> Model {
  case cost_amount_cents(model.cost_amount) {
    Error(Nil) -> Model(..model, cost_form_error: True)
    Ok(amount_cents) -> {
      let cost =
        construction_costs.ActualCost(
          incurred_on: string.trim(model.cost_date),
          description: string.trim(model.cost_description),
          category: string.trim(model.selected_category),
          amount_cents: amount_cents,
        )
      case construction_costs.summarise_actual_costs([cost]) {
        Error(_) -> Model(..model, cost_form_error: True)
        Ok(_) ->
          Model(
            ..model,
            construction_costs: list.append(model.construction_costs, [cost]),
            cost_description: "",
            cost_amount: "",
            cost_form_error: False,
          )
      }
    }
  }
}

fn save_category(model: Model) -> Model {
  let category = string.trim(model.new_category)
  case
    category == "" || category_exists(model.construction_categories, category)
  {
    True -> model
    False ->
      Model(
        ..model,
        construction_categories: list.append(model.construction_categories, [
          category,
        ]),
        selected_category: category,
        category_form_open: False,
        new_category: "",
      )
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
    expenses -> list.map(expenses, view_expense)
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
          [class("add-button"), type_("button"), event.on_click(AddExpense)],
          [
            html.span([class("add-icon"), attribute("aria-hidden", "true")], [
              html.text("+"),
            ]),
            html.text("Add an expense"),
          ],
        ),
        html.p([class("privacy-note")], [
          html.text("Changes are not saved yet."),
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
            html.text("Category totals will appear after your first entry."),
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
    [] -> [
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
              event.on_click(AddActualCost),
            ],
            [
              html.span([class("add-icon"), attribute("aria-hidden", "true")], [
                html.text("+"),
              ]),
              html.text("Add to history"),
            ],
          ),
          html.button(
            [
              class("text-button"),
              type_("button"),
              event.on_click(ShowCategoryForm),
            ],
            [html.text("Manage categories")],
          ),
        ]),
        html.p([class("privacy-note")], [
          html.text(
            "Stored only in this page for now; reloading clears the history.",
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
        event.on_input(ChangeNewCategory),
      ]),
      html.p([class(feedback_class)], [html.text(feedback)]),
    ]),
    html.div([class("form-actions")], [
      html.button(
        [class("add-button"), type_("button"), event.on_click(SaveCategory)],
        [html.text("Save category")],
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

fn view_expense(expense: ExpenseLine) -> Element(Message) {
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
