# JerdDesign

JerdDesign contains the design tokens and the SwiftUI components of Jerd.
Every screen uses these parts. Do not set sizes, colors, or fonts in a page.

JerdDesign ships in the app. It uses only public API: no private selector,
no underscored key, and no snapshot or preview code. A test reads the sources
and enforces this (`PrivateInterfacePolicyTests`). The snapshot renderer and the
component gallery are in [JerdSnapshotSupport](../JerdSnapshotSupport/README.md).

## Principles

1. Use system components first: grouped `Form`, `LabeledContent`, `Toggle`, `Picker`,
   `Menu`, `ProgressView`, and `ContentUnavailableView`. Add a component only when
   the system has none.
2. Show status with a symbol and a word. Never use color alone.
3. Show one status badge for each subject on a page. Rows explain the status.
4. Give each page header not more than one primary action: the next step.
5. Give every control a spoken name that includes its subject, for example
   "Copy Inbox URL" or "Site status". A status always has a subject: `PageHeader`
   takes a `NamedStatus`, and `StatusBadge` and `StatusIndicator` need a label.
6. Give every control that UI tests use a stable accessibility identifier. Pass
   `identifier:` to `PageAction`, `SheetConfirmation`, `SummaryCard`, and
   `InlineMessage`. Copy, path, and dismiss buttons derive theirs from their subject.
7. Use semantic colors only. Check light, dark, and Increase Contrast.
8. Make every page work at 820 × 540 and at 980 × 660.

## Tokens

| Token | Use |
| --- | --- |
| `Spacing` | The 2–32 pt scale for all padding and stack spacing. |
| `Radius` | `small` 6, `medium` 10 (banners), `large` 14 (cards), `iconTile(side:)`. |
| `TextRole` | Fonts by role. Apply with `.textRole(_:)`. Titles get the header trait. Every path uses `.path`. |
| `StatusTone` | `ready`, `busy`, `idle`, `attention`, `failed`. Each has a color and a symbol. |
| `DisplayStatus`, `NamedStatus` | A status label and its tone; with its spoken subject for a header. |
| `MessageKind` | `info`, `success`, `warning`, `error` for `InlineMessage`. |
| `ServiceTint` | The tint of each area. Use it only for icon tiles, not for status. |
| `Opacity` | Tinted fills and outlines, with stronger outlines for Increase Contrast. |
| `PageMetrics` | One centered column (680 pt maximum) for header, banners, sections, and cards. |
| `WindowMetrics`, `SheetSize` | Window, sidebar, and sheet sizes. A sheet height follows its content. |

### Status and message symbols

The symbols differ from the old app on purpose (spec F 4.2 and 8.4):

| Tone or kind | Symbol | Color | Reason |
| --- | --- | --- | --- |
| `ready` | `checkmark.circle.fill` | green | Unchanged. |
| `busy` | spinner, `clock.fill` with Reduce Motion | blue | Spec 8.4 asks that busy and attention differ; both were orange. |
| `idle` | `stop.circle` | gray | Unchanged. |
| `attention`, `warning` | `exclamationmark.triangle.fill` | orange | The triangle is the macOS symbol for "act now". |
| `failed`, `error` | `xmark.octagon.fill` | red | A stop sign, so failed and attention also differ in shape. |
| `info` | `info.circle.fill` | blue | A filled symbol, like the others. |
| `success` | `checkmark.circle.fill` | green | The same as `ready`. |

`StatusToneTests` and `MessageKindTests` pin this mapping.

## Components

| Component | When to use it |
| --- | --- |
| `FormPage` | A settings or detail page: fixed `PageHeader`, banners, grouped form. |
| `PageScaffold` | A page with free content, for example dashboard cards. |
| `PageHeader`, `PageAction` | Title, subtitle, status badge, secondary actions, one primary action. |
| `StatusBadge`, `StatusIndicator` | Status in headers and cards; compact status in sidebar rows. |
| `ServiceIcon` | A tinted symbol tile next to a title. VoiceOver ignores it. |
| `SidebarRow`, `SidebarFooter` | Sidebar items, and the one footer: Add button or menu, and a caption. |
| `ValueRow`, `CopyButton` | A read-only value with middle truncation and an optional copy button. Not for paths. |
| `ActionRow` | A title, optional detail, and trailing buttons in a form. |
| `PathRow` | Every file or folder path, with Show in Finder. |
| `FormFooter` | The one style for text under a form section. |
| `InlineMessage` | A message in a row, or a dismissible banner at the top of a page. |
| `EmptyState` | A page with no content yet, with its first action. |
| `SheetScaffold`, `SheetConfirmation` | Every sheet. Escape cancels. Return confirms if not destructive. |
| `SummaryCard` | A dashboard card: icon, title, status, summary, actions, Open. |
| `OperationBanner` | Global progress with a message and an optional Stop button. |
| `detailColumn(copyFeedback:operation:)` | The bottom of the detail column: operation banner and copy toast. |
| `CopyFeedbackMessage`, `CopyFeedbackToast` | A "Copied" event and its toast. |
| `MessageAnnouncer` | Speaks new warnings, errors, and copy confirmations to VoiceOver. |
| `BusyIndicator` | A labelled spinner for toolbars and headers. |
| `AccessibilityIdentifier` | Builds stable identifiers, for example `copy.inbox-url`. |

### Window layout

Keep the copy feedback state (`CopyFeedbackMessage?`) at the window level, so the
sidebar, the menus, and the pages can all set it. Apply
`detailColumn(copyFeedback:operation:)` to the detail column of the
`NavigationSplitView`. It puts the `OperationBanner` at the bottom edge and draws the
toast above it. Do not put the toast or the banner on the whole split view: the
toast then covers the operation message, and the banner covers the sidebar footer.

### Sheets

`SheetScaffold` has a fixed width and takes the height of its content, between
`SheetSize.minimumHeight` and `maximumHeight`. Longer content scrolls. Do not set a
sheet height in a page. On macOS 15 and later the scaffold measures its form; on
macOS 14 it uses the ideal height that the system form reports. While
`workingMessage` shows, Confirm is disabled and Cancel stays enabled. Return presses the
confirm button by default; pass `returnKey: .cancel` to make a plain Done or Close the
default button, or `.none` for no Return shortcut. A destructive confirm never gets Return,
and Escape always cancels. A destructive
confirm uses the plain push button label, because red text on a gray bezel is
hard to read.

### Announcements

`InlineMessage` announces warnings and errors when they appear and each time their
text changes, in the row and the banner style. A repeated `CopyFeedbackMessage`
with the same text is announced again. A page that stays alive but is not on
screen sets `.environment(\.messageAnnouncer, .silent)`, so it does not speak.

## Snapshots

`./dev snapshots [PAGE...]` renders the component gallery and the registered pages.
See [JerdSnapshotSupport](../JerdSnapshotSupport/README.md).
