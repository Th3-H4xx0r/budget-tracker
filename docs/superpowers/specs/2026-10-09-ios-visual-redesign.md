# iOS Visual Redesign (IntelliStock design language)

## Purpose

This spec restyles MoneyMatter for iOS in the design language of the user's IntelliStock app: Apple Stocks with a single violet accent. It is calm, system-native and dense with meaning, and it carries no decoration.

The source of truth for the language is IntelliStock:

- spec: `/Users/pranavkrishna/PranavFiles/coding-projects/IntelliStock/docs/superpowers/specs/2026-10-02-ios-ui-redesign.md`;
- code: `/Users/pranavkrishna/PranavFiles/coding-projects/IntelliStock/ios/IntelliStock/DesignSystem/` (`Tokens.swift`, `Typography.swift`, `Components/*`);
- charts: `ScrubbableAreaChart.swift`, `Sparkline.swift`, `ChartDrawIn.swift`, `HeroValueHeader.swift`, `StatGrid.swift`, `EntityRow.swift`, `StatusBadge.swift`, `SettingsIconTile.swift`, `ToolbarMenu.swift`, `EmptyState.swift`, `CommonWidgets.swift`;
- screens: `Features/Dashboard/Views/DashboardView.swift`, `App/MainTabView.swift`, `Features/Chatbot/Views/ChatAccessoryView.swift`.

Read those files and port the patterns. Don't copy IntelliStock-specific domain code.

Behaviour does not change. This is presentation only, and every existing binding, call and navigation path stays.

## Tokens

All tokens live in `ios/MoneyMatter/DesignSystem/`.

| Token                 | Value                                                                                                                                                                                                                                                                                                                                                                              |
| --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Accent                | `AccentColor` = **#6D28D9** light / **#A78BFA** dark. It is the only brand colour.                                                                                                                                                                                                                                                                                                 |
| `onAccent`            | White in light mode, **#04040C** in dark mode, for text on accent fills.                                                                                                                                                                                                                                                                                                           |
| Up / income           | `.green`, paired with `arrow.up.right`.                                                                                                                                                                                                                                                                                                                                            |
| Down / expense        | `.red` for losses and negative changes, paired with `arrow.down.right`. Plain expense amounts in lists stay `.primary` with a leading minus.                                                                                                                                                                                                                                       |
| Warning / info / cash | `.orange` / `.blue` / `.teal`.                                                                                                                                                                                                                                                                                                                                                     |
| Canvas                | `.systemGroupedBackground`.                                                                                                                                                                                                                                                                                                                                                        |
| Panel                 | `.secondarySystemGroupedBackground`.                                                                                                                                                                                                                                                                                                                                               |
| Inset                 | `.tertiarySystemGroupedBackground`.                                                                                                                                                                                                                                                                                                                                                |
| Tint fill             | 0.15 opacity.                                                                                                                                                                                                                                                                                                                                                                      |
| Chart area fill       | 0.12 opacity.                                                                                                                                                                                                                                                                                                                                                                      |
| Text on a tint        | In light mode, coloured text on a tint uses `color.mix(with: .black, by: 0.4)`.                                                                                                                                                                                                                                                                                                    |
| Spacing               | 2 / 4 / 8 / 12 / 16 / 20 / 28. Cards use 16 padding and 12 between groups.                                                                                                                                                                                                                                                                                                         |
| Corner radius         | Card 22, control 12, small 8, all `.continuous`. Icon tiles use 30% of their side (24% for Settings tiles).                                                                                                                                                                                                                                                                        |
| Typography            | SF text styles only. The hero value is 40 pt bold, scaled relative to `.largeTitle`, with `.monospacedDigit()`. Groups use `.title3.bold()`, rows `.headline` plus `.subheadline` `.secondary`, metadata `.footnote`, stat labels `.caption`, badges and axes `.caption2`. Every number is `.monospacedDigit()`. Everything is sentence case: no uppercase and no letter tracking. |

**Forbidden:** gradients, mesh or glow backgrounds, shadows, borders on cards, nested cards, and decorative colour.

**Liquid Glass** is allowed only on floating, functional controls: the tab bar accessory, glass circle buttons on hero screens, toasts, and `.glassProminent` / `.glass` buttons.

## Components

Port these into `ios/MoneyMatter/DesignSystem/`. Replace or update the existing shared views so every screen picks them up.

- **`DSCard`:** a 22-radius panel used only for heroes and charts, never nested. `.cardStyle()` maps to it. `.glassCardStyle()` maps to it too, because glass is not used for cards.
- **`HeroValueHeader`:**
  - value at hero size with `.contentTransition(.numericText(value:))` and `.snappy`;
  - a change line with an arrow, coloured green or red;
  - an optional status line (`StatusDot` plus words, such as "Updated just now").
- **`ScrubbableAreaChart`:**
  - monotone 2 pt line over a 12% area fill, with one dotted baseline `RuleMark`;
  - hidden axes, and up to 4 `.caption2` date labels underneath;
  - `chartXSelection` scrubbing with a hairline, a 9 pt dot, and `.sensoryFeedback(.selection)` on each snap;
  - a pulsing end dot;
  - a draw-in mask over 0.9 s, ease-out, respecting Reduce Motion;
  - green when the period is up, red when it is down. A neutral series uses the accent.
- **`Sparkline`:** a 1.5 pt line with no fill and an optional dotted baseline. It draws in over 0.65 s.
- **`StatGrid` / `StatCell`:** 2 or 3 columns. Each cell has a `.caption` `.secondary` label over a `.body` monospaced value. It drops a column at accessibility text sizes.
- **`EntityRow`:** a leading `IconTile` (32 pt) or logo, a `.headline` title over a `.subheadline` `.secondary` subtitle, and a trailing value over a coloured `.footnote` detail. Use it as the label of a `NavigationLink`. Secondary actions go in swipe actions and the context menu only. `TransactionRow` and `AccountRow` adopt this structure.
- **`IconTile`:** a 32 pt rounded tile filled with the category or brand colour at 15%, with a coloured glyph. **`SettingsIconTile`:** a 30 pt tile with a solid colour fill and a white glyph.
- **`StatusBadge`:**
  - `.caption2.weight(.semibold)`, `onTint` text on a 15% tint capsule, padding 7×3;
  - the fraud badge, "Unreviewed", "Archived" and every other badge use this style;
  - `StatusDot`: an 8 pt dot plus a `.secondary` word, with a phase-animated pulse.
- **Buttons:** primary is `.borderedProminent` with an `onAccent` foreground. A floating primary is `.glassProminent`. Secondary actions are accent-coloured list rows (`InlineActionRow`), never tinted capsules.
- **Section headers:** system headers with `.textCase(nil)`. A group header is `.title3.bold()` with an optional trailing small segmented picker.
- **Toolbars:**
  - a bare `plus` to create, and a bare `ellipsis` `Menu` for everything else;
  - no refresh buttons, because every list uses pull-to-refresh.
- **States:**
  - empty: `ContentUnavailableView` with a prominent action;
  - loading: `.redacted(.placeholder)` over the real layout;
  - error: an `ErrorRow` (red text on a 15% red tint, 12 radius, with Retry).

## Screen patterns

- **Default container:** `List` with `.listStyle(.insetGrouped)` on the grouped canvas. Cards are only for charts and summaries that aren't row-shaped.
- **Titles:** tab roots use large titles. Pushed screens use inline titles set to the entity name. A title is never repeated in the content.
- **Detail screens:** a `HeroValueHeader` (amount or balance), then a "Details" `StatGrid`, then sections of rows.
- **Sheets:** `.presentationDetents([.medium, .large])` with a drag indicator where it fits.

### Home

Home is laid out like the IntelliStock dashboard:

1. **Header:** the navigation bar is hidden. At the top right sit glass circle buttons for notifications (with the unread badge) and profile/settings.
2. **Hero:** net worth as a `HeroValueHeader`, with the change versus the start of the range and "Updated just now".
3. **Chart:** a full-width `ScrubbableAreaChart` of balance history with a range picker (1M / 3M / 6M / 1Y / All). Scrubbing updates the hero value.
4. **Customised widgets:** the existing customization still decides which widgets appear and in what order, rendered in this style:
   - **Accounts:** top accounts as `EntityRow`s with sparklines.
   - **Spending:** this month's total in the hero style, plus a donut in violet ramps (from IntelliStock's `Sector3DGeometry` palette) and category rows.
   - **Latest transactions.**
   - **Upcoming payments.**
   - **Remaining widgets:** each as a titled section or card.
5. **Review:** with a non-empty queue, a compact review row in the list ("8 transactions to review", a shield `IconTile`, and a fraud badge if any) in place of the big card.

### Tab bar

- The system `Tab` API, with symbols drawn filled.
- **`tabViewBottomAccessory`:** a glass capsule.
  - **Queue not empty:** a shield with the accent badge count, "8 to review", and a `+` button for quick add. Tapping the review part opens the card stack; tapping `+` opens the new-transaction editor.
  - **Queue empty:** only "Add transaction" with a `+`.

  Modelled on IntelliStock's `ChatAccessoryView`.

### Review stack

- A panel card with no glass on the card.
- The amount at hero size, then a `StatGrid` of details.
- The three actions as a glass button group, which floats.
- Swipe behaviour is unchanged.

### Other screens

- **Settings hub:** an inset-grouped list with `SettingsIconTile`s in a distinct system colour per row, as in iOS Settings.
- **Accounts:** the hero is net worth, followed by grouped `EntityRow`s with balances and sparklines where a history exists, and an Assets section with icon tiles.
- **Transactions:** day sections, each with a `.subheadline` header carrying the day's net. Rows are `EntityRow`s. The detail screen is a hero amount plus a `StatGrid`.
- **Planning and Insights:** charts use `ScrubbableAreaChart` and `Sparkline` styling; budgets use utilization bars in the accent (red when over budget); stats use `StatGrid`.
- **Auth and onboarding:**
  - a plain grouped canvas, with no glow or gradient;
  - the app mark as an accent `IconTile` (64 pt);
  - an inset-grouped field card;
  - a `.glassProminent` primary pill;
  - Google and GitHub as `.glass` buttons with brand logos;
  - the server chip as a `StatusBadge`-style capsule.

## Acceptance

1. The tokens and components exist in `DesignSystem/`, and every screen uses them.
2. No gradients, shadows or nested cards remain.
3. The app builds with zero errors, and all Kit and app tests pass.
4. Simulator screenshots of Home, Accounts, Transactions, the review stack, Planning, Insights, Settings and Sign In look calm and Stocks-like in both light and dark mode.
