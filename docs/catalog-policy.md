# Catalog policy inputs

`Packages/NativePolicy` exposes `NativePolicy.catalog`, a small `Catalog` value for a future
plugin catalog consumer. These are additive package-level inputs. This change does not activate
a catalog or wire enforcement into a fetch/install path. It does not block downloads or create
a security boundary, and it selects no official catalog endpoint.

| Preference key | Typed value | Accepted input | Default |
| --- | --- | --- | --- |
| `policy.catalog.enabled` | `catalog.isEnabled` | Boolean | `true` (allowed) |
| `policy.catalog.indexURL` | `catalog.indexURL` | HTTP or HTTPS URL string with a host | `nil` |

Each key follows the existing precedence: valid organization value, then valid user value
exposed by the policy source, then the default. Invalid values are ignored and reported in
`diagnostics` with their key and origin. Only valid organization values enter `managedKeys`.
Both keys are recognized, so they produce no unknown-key warnings. URL validation reuses the
existing web URL parser used for update feeds.

The future consumer must check `catalog.isEnabled` before fetching and use `catalog.indexURL`
when present. An enabled catalog permits a future consumer to operate; resolving policy alone
starts no network activity. A mirror URL can remain configured while the catalog is disabled.

`policy.plugins.allowed` remains separate: it controls which manifest plugins may load, with
the existing built-in exemptions unchanged. Catalog inputs do not alter plugin activation,
feature defaults, `scriptsEnabled`, or other policy values. There is no offline master switch,
fetcher, installer, registry integration, or new MDM profile in this change. The existing sample
profile includes both keys as validated inputs for a future consumer, with the catalog disabled
and an example mirror URL. They have no runtime effect until consumer integration.
