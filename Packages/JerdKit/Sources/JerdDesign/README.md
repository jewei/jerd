# JerdDesign

JerdDesign contains the design tokens and the SwiftUI components of Jerd.
Every screen uses these parts. Do not set sizes, colors, or fonts in a page.

## Principles

1. Use system components first: grouped `Form`, `LabeledContent`, `Toggle`, `Picker`,
   `Menu`, `ProgressView`, and `ContentUnavailableView`. Add a component only when
   the system has none.
2. Show status with a symbol and a word. Never use color alone.
3. Show one status badge for each subject on a page. Rows explain the status.
4. Give each page header not more than one primary action: the next step.
5. Give every control a spoken name that includes its subject, for example
   "Copy Inbox URL" or "Site status".
6. Use semantic colors only. Check light, dark, and Increase Contrast.
7. Make every page work at 820 × 540 and at 980 × 660.

## Tokens

| Token | Use |
| --- | --- |
| `Spacing` | The 2–32 pt scale for all padding and stack spacing. |
| `Radius` | `small` 6, `medium` 10 (banners), `large` 14 (cards), `iconTile(side:)`. |
| `TextRole` | Fonts by role. Apply with `.textRole(_:)`. Titles get the header trait. |
| `StatusTone` | `ready`, `busy`, `idle`, `attention`, `failed`. Each has a color and a symbol. |
| `DisplayStatus` | A status label and its tone, for example `("Ready", .ready)`. |
| `MessageKind` | `info`, `success`, `warning`, `error` for `InlineMessage`. |
| `ServiceTint` | The tint of each area. Use it only for icon tiles, not for status. |
| `Opacity` | Tinted fills and outlines, with stronger outlines for Increase Contrast. |
| `PageMetrics` | One centered column (680 pt maximum) for header, banners, and sections. |
| `WindowMetrics`, `SheetSize` | Window, sidebar, and sheet sizes. |

## Components

| Component | When to use it |
| --- | --- |
| `FormPage` | A settings or detail page: fixed `PageHeader`, banners, grouped form. |
| `PageScaffold` | A page with free content, for example dashboard cards. |
| `PageHeader`, `PageAction` | Title, subtitle, status badge, secondary actions, one primary action. |
| `StatusBadge`, `StatusIndicator` | Status in headers and cards; compact status in sidebar rows. |
| `ServiceIcon` | A tinted symbol tile next to a title. VoiceOver ignores it. |
| `SidebarRow`, `SidebarFooter` | Sidebar items, and the one footer: Add button or menu, and a caption. |
| `ValueRow`, `CopyButton` | A read-only value with middle truncation and an optional copy button. |
| `ActionRow` | A title, optional detail, and trailing buttons in a form. |
| `PathRow` | A file or folder path with Show in Finder. |
| `FormFooter` | The one style for text under a form section. |
| `InlineMessage` | A message in a row, or a dismissible banner at the top of a page. |
| `EmptyState` | A page with no content yet, with its first action. |
| `SheetScaffold`, `SheetConfirmation` | Every sheet. Escape cancels. Return confirms if not destructive. |
| `copyFeedback(_:)`, `CopyFeedbackToast` | A "Copied" toast that VoiceOver announces. Apply it at the window root. |
| `SummaryCard` | A dashboard card: icon, title, status, summary, actions, Open. |
| `OperationBanner` | Global progress with a message and an optional Stop button. |
| `BusyIndicator` | A labelled spinner for toolbars and headers. |

Put `OperationBanner` in the detail column with `.safeAreaInset(edge: .bottom)`.
If you put it on the whole split view, it covers the sidebar footer.

## Snapshots

Render all registered views to PNG files in `.build/snapshots`:

```sh
swift run --package-path Packages/JerdKit jerd-snapshots [--output DIR] [--filter NAME...] [--list]
```

File names are `<name>-<appearance>-<size>.png`, for example
`gallery-workspace-dark-compact.png`. The renderer draws an offscreen window at
scale 2. It does not show a window and does not need screen recording permission.

To add a page, add one line in `Sources/JerdSnapshots/SnapshotCatalog+Jerd.swift`:

```swift
catalog.add("sites-running") { WorkspaceView(model: .sitesRunning) }
```

Known limits of offscreen rendering: materials (`.bar`, `.regularMaterial`) draw as
flat colors, spinners show one fixed frame, and Liquid Glass toolbar effects do not
show. Look at every PNG after a change.
