# lucentLIMS

A native front end for lucentBASE, written in SwiftUI. It follows
[lucentAndShiny](../lucentandshiny) and keeps its structure: Collections, Locations,
Scientific and Management. One code base runs on macOS, iPadOS and iOS.

For now the app works on **mock data in memory**. Nothing is read from or written to a
database, and every change is gone when the app quits.

## What's there

| Section | What it does |
|---|---|
| **Dashboard** | Greeting for the logged-in user, key figures, collections per week by matrix, status donut (hover or tap a sector), limit exceedances of the last 30 days, upcoming tasks, inbox |
| **Collections** | Sortable, searchable table with status filter. The inspector shows a collection's values (with limits, uncertainty, repetitions and an accept seal), its actions and where it was sampled. Pending values can be entered there. Context menu: accept all values, show on map |
| **New collection** | Like lucentAndShiny's "Add Collection" dialog: next identifier, matrix, class, spot or site, plus the methods the class plans |
| **Locations** | Spots and sites on a map. A selected location shows its position, address and a time series of any variable measured there, with the limit drawn in. The chart opens on the variable that exceeded its limit most often |
| **Methods** | Actions with their variables, units, uncertainties, limits, formulas, dependencies, SOP, devices and people |
| **Variables & Units** | Variables, units with notations, dimensions, matrices and collection classes |
| **People, Devices, Tasks, SOPs** | Organizations and roles, devices (switch them on and off), tasks by due date, SOP documents with acceptance state and SHA-256 |

Pages link to each other: a person in a method, a method in a collection, an SOP in a method
and so on. On the Mac there are menu commands: **File → New Collection…** (⇧⌘N) and a **Go**
menu (⌘1 to ⌘9).

## Building

Requires Xcode 26 or later (built with Xcode 27.1). Deployment targets are macOS 26 and iOS 26.

Open `lucentLIMS.xcodeproj`, choose the `lucentLIMS` scheme and "My Mac" or a simulator, and run.

From the command line:

```bash
xcodebuild -project lucentLIMS.xcodeproj -scheme lucentLIMS -destination 'platform=macOS' build
```

```bash
xcodebuild -project lucentLIMS.xcodeproj -scheme lucentLIMS -destination 'platform=macOS' test
```

If `xcode-select -p` points to the Command Line Tools, prefix the commands with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, or switch once with
`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.

The Mac app is signed to run locally and sandboxed, with outgoing connections allowed for the
map tiles.

## Layout

```
lucentLIMS/
  App/          entry point, menu commands, sidebar, navigation state
  Model/        lucentBASE types, numbering scheme, mock data, LabStore
  Views/        one folder per sidebar group, plus shared components
lucentLIMSTests/  Swift Testing: numbering scheme and store logic
scripts/make-icon.swift  draws the app icon
```

`LabStore` is the only place the views get data from. Connecting lucentBASE means filling
`LabStore` (or the `LabData` it starts from) from the database instead of `MockData`.

## The data model

The types follow the lucentBASE tables. Some names are prefixed where they would collide with
Foundation or SwiftUI:

| lucentBASE | Swift |
|---|---|
| `collection` | `LabCollection` |
| `action`, `j_action_variable`, `j_action_collection_class` | `LabAction`, `ActionVariable`, `LabData.classActions` |
| `j_action_dependency`, `j_action_implication` | `LabAction.dependsOn`, `LabAction.implies` |
| `value` | `LabValue` (the decimal, text, boolean and datetime columns become one `Reading`) |
| `unit`, `unit_notation` | `LabUnit` with `notations` |
| `dimension` | `PhysicalDimension` |
| `sop`, `link`, `j_sop_link`, `j_sop_person` | `SOP` with `documents` (`SOPDocument`) and `people` |
| `site`, `spot`, `crs`, `v_address` | `Site`, `Spot`, `CRS`, `Address` |
| `person`, `organization`, `j_person_organization` | `Person` (with `position`), `Organization` |
| `task`, `message` | `LabTask`, `Message` |

As in lucentBASE, `spot.x` is the latitude and `spot.y` the longitude.

The mock data needs a few fields lucentBASE doesn't have yet. They are marked "Not in
lucentBASE" in [Models.swift](lucentLIMS/Model/Models.swift):

- `collection`: when and by whom it was sampled;
- `j_action_variable`: limits and display precision;
- `task.done` and `message.sent_at`.

Not modelled yet: `raw_value`, `constant`, `j_value_value`, `j_variable_variable`, and the
"Compound" option of the old dialog.

A collection's status is derived from its values: *registered* (none), *in analysis* (some
of the planned ones), *in review* (all, not all accepted), *approved* (all accepted).

### Mock data

[MockData.swift](lucentLIMS/Model/MockData.swift) uses the demo data of lucentAndShiny
(people, matrices, the collection class "Zeitreihe", the spots "Test 1" and "Garten") and adds
about 100 collections over twelve weeks around Karlsruhe. It's generated with a seeded random
generator, so it looks the same on every launch, and relative to the current date, so the
dashboard is always up to date. It has stories to find: nitrate rising above the limit at
GWM 12, lead at the tap in Labor 2.14 confirmed by repetitions, traffic exposure at the
Messcontainer.

The logged-in user is the person whose `unix_account` matches the macOS user name, as in
lucentAndShiny. If none matches, it's the first person.

## Collection identifiers

Identifiers come from the "mixed radix" numbering of lucentAndShiny's `las.yaml`, with the
first four segments: a digit, a colour, a digit and a Greek letter, joined by `·`. Sequence
number 1000 is `0·Cyan·1·Rho`. Consecutive identifiers differ in the last segment, which
makes them hard to mix up. The scheme holds 16,800 identifiers. See
[NumberingScheme.swift](lucentLIMS/Model/NumberingScheme.swift).

## Debug launch arguments

Debug builds can open a screen directly, which helps with screenshots and simulator runs
without clicking:

```bash
xcrun simctl launch booted com.redhsoft.lucentLIMS -section locations -location spot:10
```

`-section` takes a sidebar item (`dashboard`, `collections`, `locations`, `methods`,
`variables`, `people`, `devices`, `tasks`, `sops`). `-route` pushes a page
(`collection:96`, `method:5`, `person:28`, `sop:4`), `-collection <id>` selects a
collection, `-location spot:<id>|site:<id>` a location, and `-newCollection YES` opens the
dialog.

## App icon

`swift scripts/make-icon.swift <directory>` draws `icon-ios.png` and `icon-mac.png`. The
asset catalog holds those images, with the Mac sizes scaled using `sips`.
