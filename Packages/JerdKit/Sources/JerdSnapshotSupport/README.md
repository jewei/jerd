# JerdSnapshotSupport

JerdSnapshotSupport renders SwiftUI views to PNG files offscreen, and contains the
component gallery of JerdDesign. Only the `jerd-snapshots` executable
(`JerdSnapshots`), test targets, and `JerdUIFixtures` may import it. The app never
links it: it contains the private AppKit overrides that make an offscreen window
draw as the active window (`ActiveWindow`).

## Render

```sh
./dev snapshots                    # every entry
./dev snapshots gallery-status     # one entry, or every entry named gallery-status-*
swift run --package-path Packages/JerdKit jerd-snapshots [--output DIR] [--list] [NAME...]
```

`--filter NAME...` is the same as `NAME` arguments. Exit status: 0 success,
1 rendering or writing failed, 2 a usage error or an unknown page name.

File names are `<name>-<appearance>-<size>.png`, for example
`gallery-workspace-dark-compact.png`. The appearances are `light`, `dark`,
`light-contrast`, and `dark-contrast`. The renderer draws an offscreen window at
scale 2. It does not show a window and does not need screen recording permission.
After a full run (no names), the command removes PNG files that no entry writes
any more, so a renamed page leaves no stale image. Other files stay.

## Register a page

Add one line in `Sources/JerdSnapshots/SnapshotCatalog+Jerd.swift`:

```swift
catalog.add("sites-running") { WorkspaceView(model: .sitesRunning) }
```

By default an entry renders the full window with its toolbar, at both window sizes
(980 × 660 and 820 × 540), in light and dark. Options of `add`:

| Option | Use |
| --- | --- |
| `sizes:` | Other canvases. `SnapshotSize.fittingHeight(name:width:)` takes the ideal height of the view, for sheets. |
| `appearances:` | Add `.lightContrast` and `.darkContrast` for pages with tinted fills and outlines. |
| `chrome: .content` | Only the view, without the window frame. |
| `isReady:` | For content that loads in `.task`: the renderer waits until the closure returns true. |

The renderer runs layout passes until `isReady` is true and two passes in a row
draw the same pixels. It suspends between passes, so `.task` and `onChange` work
runs. A view that does not settle in 150 passes (about 3 s) fails with its file name.

A capture only reads the window. It draws with `displayIgnoringOpacity(_:in:)`,
not with `cacheDisplay(in:to:)`: `cacheDisplay` makes the AppKit controls that
SwiftUI hosts (window buttons, a segmented toolbar picker) lay out and render
again during the capture, and whether they do depends on timing. The toolbar
text then moved by part of a point in some renderings.

## Fixed settings

`SnapshotProcessSettings` writes these values into the argument domain of the
snapshot process before AppKit starts. The images then do not depend on the
settings of the developer who renders them:

| Setting | Fixed value |
| --- | --- |
| Accent and highlight color | Blue, the "Multicolor" default of an app without its own accent |
| Show scroll bars | When scrolling (overlay scrollers) |
| Sidebar icon size | Medium |
| Language and region | English (US), `en_US` |
| Appearance | Light; each window sets light or dark itself |
| Increase Contrast | Off, or on in the contrast pass |

The SwiftUI environment also fixes the locale, time zone (GMT), calendar
(Gregorian), and color scheme, and turns off animations. A test
(`SnapshotExecutableTests`) renders with unusual user settings and proves that
the bytes do not change.

## Increase Contrast

AppKit reads Increase Contrast once, when the application starts, and
`NSAppearance(named: .accessibilityHighContrastAqua)` returns plain Aqua. So the
command renders the light and dark variants first, then starts itself again with
`--contrast-pass`. That process turns on the real Increase Contrast setting, so
AppKit controls and SwiftUI both draw as a user with Increase Contrast sees them.
Before each rendering, the renderer checks the appearance that AppKit resolves for
the window, and refuses to write a file whose name does not match it.

## What can still vary

- The macOS version: system fonts, control metrics, and materials change between
  releases. Compare images only from one macOS version.
- Accessibility settings that are not fixed: Reduce Transparency, Differentiate
  Without Color, and Reduce Motion. With Reduce Motion on, busy states show a clock
  symbol instead of a spinner frame.
- Fonts that a user installs or removes, when a view asks for a font by name.
- The Mac hardware does not matter: the scale is always 2 and the color space is sRGB.

## Known limits of offscreen rendering

Materials (`.bar`, `.regularMaterial`) draw as flat colors, spinners show one fixed
frame, and Liquid Glass toolbar effects do not show. Look at every PNG after a change.
