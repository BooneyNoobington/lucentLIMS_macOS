<p align="center"><img src="Branding/lucentLIMS-logo.svg" alt="lucentLIMS" width="420"></p>

# lucentLIMS

A native front end for lucentBASE, written in SwiftUI. It follows
[lucentAndShiny](../lucentandshiny) and keeps its structure: Collections, Locations,
Scientific and Management. One code base runs on macOS, iPadOS and iOS.

The data comes from one of two places:

- **Demo data**, the default: in memory, no setup, and changes are gone when the app quits.
- **lucentBASE through [lucentAPI](../lucentAPI)**: what you see and change is in the
  database, under your name, within what your roles allow.

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

## Connecting to lucentAPI

Open the connection settings: **lucentLIMS → Settings** (⌘,) on the Mac, or the gear at the
bottom of the sidebar elsewhere. Choose "lucentAPI server" and enter the server's address,
then sign in in one of two ways:

- **OpenID Connect**, for real use. Enter the identity provider's issuer
  (e.g. `https://id.example.org/realms/lucent`) and the client ID (default `lucentlims`). At
  the provider, register lucentLIMS as a public client:
  - authorization code flow with PKCE;
  - redirect URI `lucentlims://oauth/callback`;
  - an audience mapper that adds the API's audience.

  lucentAPI's README walks through it for Keycloak. "Sign In" opens the provider's login page.
  The tokens are kept in the Keychain and renewed with the refresh token.
- **Access token**, for development: paste a token, e.g. from lucentAPI's
  `uv run python dev/mint_token.py grindel admin`.

The app loads the reference data and the collections of the last 26 weeks with their values.
Changes go to the API, and the app shows what comes back. The roles in the token decide what's
enabled:

- registering needs `sampler`;
- recording values needs `analyst`;
- accepting needs `reviewer`, and never for values you measured yourself;
- switching devices needs `admin`.

If the API refuses a change, for example because someone else changed the record in the
meantime (412), an alert says why.

The OpenID Connect flow is unit-tested against a fake provider but hasn't been tried with a
real identity provider yet. The access-token way is tested end to end against lucentAPI.

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

The integration tests in [APIIntegrationTests.swift](lucentLIMSTests/APIIntegrationTests.swift)
run only against a live lucentAPI. Start its development server on port 8765 with the demo
data, then set three variables for xcodebuild (it passes on `TEST_RUNNER_…`). Set the server
first:

```bash
export TEST_RUNNER_LUCENT_TEST_SERVER=http://localhost:8765
```

Run the next two commands in the lucentAPI directory, so the tokens come from its
`dev/mint_token.py`:

```bash
export TEST_RUNNER_LUCENT_TEST_ANALYST=$(uv run python dev/mint_token.py worf sampler analyst)
```

```bash
export TEST_RUNNER_LUCENT_TEST_REVIEWER=$(uv run python dev/mint_token.py xx121 reviewer)
```

Then run the `xcodebuild … test` command above from this directory.

The client package has its own tests; run them in `Packages/LucentAPIClient`:

```bash
swift test
```

If `xcode-select -p` points to the Command Line Tools, prefix the commands with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, or switch once with
`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.

The Mac app is signed to run locally and sandboxed, with outgoing connections allowed for the
map tiles.

## Layout

```
lucentLIMS/
  App/          entry point, menu commands, sidebar, navigation, Connection
  Auth/         OpenID Connect with PKCE, token renewal, Keychain
  Model/        lucentBASE types, numbering scheme, LabStore, LabService (demo and API)
  Views/        one folder per sidebar group, settings, shared components
lucentLIMSTests/  Swift Testing: numbering, store, demo service, sign-in, API integration
Packages/LucentAPIClient/  the API client, a Swift package without dependencies
scripts/make-icon.swift  draws the app icon
```

The layers can be taken apart:

- **Views:** they only talk to `LabStore`.
- **`LabStore`:** gets its data from a `LabService` and sends changes there, then replaces its
  copy with what comes back.
- **`MockLabService`:** the demo data. It follows the API's rules: identifiers, repetitions,
  four-eyes.
- **`APILabService`:** maps the client package's types onto the app's.
- **`LucentAPIClient`:** knows nothing about the app, so other Swift programs can use it.

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

The app needs a few fields lucentBASE doesn't have yet. They are marked "Not in lucentBASE"
in [Models.swift](lucentLIMS/Model/Models.swift), and lucentAPI's
`sql/lucentbase-additions.sql` adds them to the database:

- `collection`: when and by whom it was sampled;
- `j_action_variable`: limits and display precision;
- `task.done` and `message.sent_at`.

A value's time, person and device come from its latest `raw_value`. Not modelled yet:
`constant`, `j_value_value`, `j_variable_variable`, and the "Compound" option of the old
dialog.

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

- `-section` takes a sidebar item: `dashboard`, `collections`, `locations`, `methods`,
  `variables`, `people`, `devices`, `tasks` or `sops`.
- `-route` pushes a page: `collection:96`, `method:5`, `person:28`, `sop:4`.
- `-collection <id>` selects a collection.
- `-location spot:<id>` or `site:<id>` selects a location.
- `-newCollection YES` opens the dialog.

The settings can be set the same way, and a debug build takes a token on the command line:

```bash
xcrun simctl launch booted com.redhsoft.lucentLIMS -LucentSource server -LucentServerURL http://localhost:8765 -LucentSignInMethod accessToken -LucentAccessToken "$TOKEN"
```

## Logo and app icon

The logo is two translucent cards laid over each other to form an L. [Branding/](Branding)
holds it as SVG: the mark (`lucentLIMS-icon.svg`), a one-colour version
(`lucentLIMS-icon-monochrome.svg`) and the mark with the wordmark (`lucentLIMS-logo.svg`).

| | |
|---|---|
| Vertical card | `#59B9F4` |
| Horizontal card | `#7ADFC8` |
| Overlap | `#168ED0`, also the app's accent colour (`#59B9F4` in dark mode) |
| Wordmark | `#252B34` ("lucent" bold, "LIMS" light) |

In the app, `LucentMark` and `LucentLogo` ([Logo.swift](lucentLIMS/Views/Components/Logo.swift))
draw it from the same geometry, so it stays sharp at every size. It appears at the top of
the sidebar and on the sign-in and loading screens.

`swift scripts/make-icon.swift <directory>` draws the app icons from that geometry:

- `icon-ios.png`, the mark on a light background;
- `icon-ios-dark.png` and `icon-ios-tinted.png`, for iOS's dark and tinted home screens;
- `icon-mac.png`, a plate with margin and shadow.

The asset catalog holds them, with the Mac sizes scaled using `sips`.
