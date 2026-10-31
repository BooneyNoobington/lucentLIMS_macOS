# LucentAPIClient

A Swift client for [lucentAPI](../../../lucentAPI): Codable types for every answer, an async
method for every endpoint, and no dependencies besides Foundation. lucentLIMS uses it, and so
can any other app on macOS 14 or iOS 17 and later.

```swift
import LucentAPIClient

let api = LucentAPIClient(baseURL: URL(string: "https://lims.example.org")!) {
    try await tokens.accessToken()  // called before every request
}

let open = try await api.collections(status: .inReview)
let collection = try await api.registerCollection(.init(matrixId: 3, collectionClass: "spot sample", spotId: 6,
                                                        actionIds: [1, 3], sampledAt: .now))
let pH = collection.values.first { $0.effectId == 5 }!
let raw = try await api.recordRawValue(.init(reading: .decimal(7.6)), for: pH.id)
let accepted = try await api.acceptRawValue(id: raw.id, etag: raw.etag)  // by someone else

// Admins manage people; roles live in lucentBASE, not in the token.
let ripley = try await api.person(id: 6)
let reviewer = try await api.setRoles([.analyst, .reviewer], of: ripley.id, etag: ripley.etag,
                                      note: "Takes over quality assurance")
```

- **Types:** they live in the `LucentAPI` namespace (`LucentAPI.Collection`,
  `LucentAPI.Value`, `LucentAPI.RawValue`, …), so they don't clash with your own. They follow
  lucentBASE: values are a collection's slots for the effects of its actions, raw values the
  readings. Property names are the JSON names
  in camel case: `matrix_id` becomes `matrixId`.
- **Errors:** a failed request throws `LucentAPIError`, with the HTTP status and lucentAPI's
  stable `code` (`four_eyes`, `precondition_failed`, `unknown_person`, …).
- **Lost updates:** records that can change carry an `etag`. Pass it back, and if someone
  changed the record meanwhile the call fails with 412.
- **Paging:** `allCollections(sampledFrom:)` and `allValues(sampledFrom:)` follow the pages
  for you.
- **Transport:** `URLSession.shared` by default. Pass your own `transport` closure to stub the
  network in tests.

The token is up to you. lucentLIMS gets it from an OpenID Connect provider (authorization
code flow with PKCE, see its `Auth/` folder) or from a pasted development token.

## Keeping it in line with the API

The client is written by hand. Generating it with swift-openapi-generator would mean
downloading and building that tool, plus a runtime package. A small client without
dependencies is easier to read and to take along. Two things keep it from drifting:

- `Tests/LucentAPIClientTests/Fixtures/openapi.json` is a copy of lucentAPI's API
  description. The tests check that every endpoint the client calls exists there, and that
  the client covers every endpoint.
- The other fixtures are lucentAPI's `examples/responses`, real answers on its demo data. The
  tests decode each of them.

When lucentAPI changes, copy both into `Tests/LucentAPIClientTests/Fixtures/` and run:

```bash
swift test
```
