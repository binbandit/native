# Adapter lockfiles

`scripts/adapters/lockfile.py` is maintainer tooling for the managed-adapter plan.
It does not change agent launches or built-in manifests. The first production pair is
`adapters/pi` ([offline adapters](enterprise/offline-adapters.md#the-built-in-pi-pair));
runtime integration is follow-up work.

Resolution is a deliberate, networked maintainer step with an installed npm that
supports lockfileVersion 3. Use a new scratch output directory:

```sh
python3 scripts/adapters/lockfile.py generate @example/adapter 1.2.3 /tmp/adapter-1.2.3
python3 scripts/adapters/lockfile.py check @example/adapter 1.2.3 /tmp/adapter-1.2.3
python3 -m unittest discover -s scripts/adapters/tests -p 'test_*.py'
```

Generation writes a minimal exact-pin `package.json`, then runs npm with
`--package-lock-only --ignore-scripts --no-audit --no-fund`. Its scratch cache is
discarded. Existing output directories are refused; failure can leave an empty
directory, but never publishes an unaudited lockfile. npm output is suppressed
because configuration and errors can contain credentials. Do not print tokens or
environment dumps when investigating failures.

The default registry is `https://registry.npmjs.org/`. Mirroring is explicit:
pass `--registry https://mirror.example/npm/` (also applied to the adapter's scope).
Registry and tarball URLs must be HTTPS without credentials, query or fragment.
Review all resolved URLs, transitive version changes and sha512 integrity changes
before accepting an update, including optional platform packages. Unknown npm
fields are preserved byte-for-byte. Check is offline: it validates both root pins,
the adapter resolution and every package record's exact SemVer, HTTPS URL and
canonical 64-byte sha512 digest. Dependency declarations must use registry specs;
ranges and npm aliases within records are normal metadata, while file and Git
sources are refused. This checks digest syntax; it does not download or verify bytes.
Required dependencies and peers must have nested or hoisted package records;
missing optional dependencies and optional peers are allowed.

The future consumer contract is `npm ci --ignore-scripts` from the reviewed pair
of files into a dedicated adapter folder, followed by direct `node <bin>` launch.
Do not enable `--omit=optional` without separately proving that adapter does not
need its optional packages. No adapter, lifecycle script or `npx` is run here.
