# PluginCatalog

A UI-free Swift 6 library for macOS 15+ and iOS 18+. It uses Foundation and system CryptoKit,
with no dependencies. Linux is unsupported; this package is outside the app and NativeHost graphs.

## Signed v1 index

```json
{"schema":1,"plugins":[{"id":"example","version":"1.0.0","repository":"https://example.org/owner/plugins","commit":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","path":"plugins/example","archiveURL":"https://example.org/assets/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/example.tar","sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","size":123}]}
```

All shown fields are required. Unknown fields are ignored; unknown schemas are rejected.
IDs are unique lowercase alphanumeric words joined by single hyphens. Versions are nonempty
display strings, not ordered semantic versions. Both URLs must be absolute HTTPS without user
information. Commits and SHA-256 pins are respectively 40 and 64 lowercase hexadecimal characters.
Paths name the plugin directory at that Git commit: relative slash-separated components with no
empty, dot or dot-dot components, backslashes or NULs. Each tar contains `plugin.json` and assets at
its root. `sha256` and positive integer `size` describe the exact uncompressed tar bytes.

Call `PluginCatalogIndex.verified(data, signature: base64Signature, publicKey: trustedKeyData)`.
The caller supplies a trusted 32-byte Ed25519 public key and a detached base64 signature (64 decoded
bytes; surrounding whitespace is accepted). Verification covers the exact UTF-8 index bytes, before
any JSON decoding. Do not reserialize, normalize whitespace or change line endings before verifying.
Failures use `PluginCatalogError`; invalid entry values identify the plugin and field. Missing fields,
wrong JSON types and invalid UTF-8 produce `malformedJSON` after signature verification succeeds.

No production URL or key is selected here. Future callers own fetching, trust configuration,
archive hash/size checks, extraction safety, manifest inspection, policy and explicit install/update
consent. This package performs no HTTP, extraction, installation or updates and changes no defaults.

Run: `nice -n 10 swift test -j 4 --package-path Packages/PluginCatalog --filter PluginCatalogIndexTests`.
