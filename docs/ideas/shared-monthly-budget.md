# Shared Monthly Household Budget

## Problem Statement

How might we help a couple or family decide, at the start of each month, how much each person should put into their shared account to cover planned household expenses, including variable costs?

## Recommended Direction

Make Cabanon a monthly planning tool rather than a ledger of purchases. Each month starts from the previous month's plan: expense names, categories, and amounts are copied as editable starting values. The household reviews and confirms its variable estimates before finalizing the month's plan.

Show the planned expense total and its change in euros and percentage from the previous month's plan. Each expense also shows its percentage of the monthly total; category totals can show their own share. Keep this forecast separate from the equal contribution calculation: subtract the manually entered shared-account balance from planned expenses, then divide the remaining amount equally among household members, distributing any leftover cents consistently.

The current application already has the equal-split calculation, a manually archived monthly contribution history, and editable household expense labels. Construction costs have categories, but household expenses do not. The household currently has one active budget rather than a distinct plan for each month, so this feature requires monthly budget persistence and household categories, not just a frontend change.

## Key Assumptions to Validate

- [ ] The household is willing to review and confirm variable estimates each month. Test the monthly flow with a couple using a few months of their real planned costs.
- [ ] The shared-account balance is entered manually and is accurate enough to calculate the required deposits. Test whether a clearly dated balance prompt is sufficient.
- [ ] Comparing planned budgets is useful even without tracking actual transactions. Confirm that users understand the percentages describe forecasts, not realized spending.
- [ ] Category names help explain the budget. Validate whether common editable defaults (housing, utilities, food, transport, and other) fit the household's vocabulary.

## MVP Scope

- Create a distinct household budget for each month.
- Start a new month by copying the previous plan's expense names, categories, and amounts as editable starting values.
- Let users review and update variable estimates each month.
- Assign a category to each planned expense and show totals by category.
- Show total planned expenses and the change in euros and percentage from the previous calendar month.
- Show each expense's share of the total planned budget; show each category's aggregate share.
- Calculate equal per-person contributions after applying the manually entered shared-account balance.
- Preserve monthly snapshots for history and comparison. If the prior calendar month's plan is missing, or its total is zero, show that the percentage comparison is unavailable rather than implying a zero change.

## Not Doing (and Why)

- Bank connections or transaction imports — they add security and integration work beyond the monthly funding decision.
- Actual-versus-planned expense reconciliation — this concept is about forecasting account funding, not bookkeeping.
- Unequal or income-proportional contributions — the agreed split is equal.
- Automatic variable-spend prediction — users want to enter their estimate; historical plans are not evidence of actual spending.

## Open Questions

- Should household categories begin with an editable set of common defaults, or be entirely created by the household?
- Should a prior month's plan become read-only once the next month is created, or remain editable with a clear update to its archived snapshot?
- Should the application distinguish fixed expenses from variable estimates explicitly, or is carrying the previous amount forward with a monthly review enough?
