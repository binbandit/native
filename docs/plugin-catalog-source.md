# On-demand plugin catalog source

`PluginCatalogSource` is the policy-aware fetch boundary in `Packages/PluginCatalog`. Construct it
with an explicit default index URL and the caller's trusted Ed25519 public key. Construction does
not fetch; only `load(policy:)` does. Pass the current effective `NativePolicy.catalog` value from
the policy loader on each call, including managed organization overrides.

A disabled catalog throws `PluginCatalogSource.LoadError.disabled` before any request or endpoint
validation. Otherwise, `catalog.indexURL` selects the mirror when present; only an absent mirror
selects the caller's default. The selected URL must be absolute HTTPS without embedded credentials
or a fragment. This boundary is stricter than the policy parser, which also accepts HTTP.

Each load fetches the exact index URL, then its sibling formed by appending `.sig` to the path:
`https://mirror.example/index.json?version=1` uses `https://mirror.example/index.json.sig?version=1`.
The signature is UTF-8 base64, with the existing verifier's whitespace rules. Original index bytes
go directly to `PluginCatalogIndex.verified`. Signature, transport and policy errors never return an
unverified index or trigger fallback to another endpoint.

The default URLSession transport accepts only HTTP 2xx responses, rejects redirects, bypasses local
cache reads and propagates cancellation. A caller may inject a `Fetch` closure, or supply a session
to `download(_:session:)` for local URLProtocol fixtures. Custom transports must preserve endpoint
and cancellation semantics. Offline failures propagate to the caller without retries or fallback.

There is no production URL/key selection, automatic fetch, background task, app registration or
changed default. Archive download, hash/size verification, safe extraction, manifest inspection,
install/update consent and UI integration remain later work. The existing index README describes
the signed format; this source adds a local NativePolicy dependency and explicit HTTP capability.
