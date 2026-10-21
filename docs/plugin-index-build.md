# Offline plugin index builder

Run with Python 3 and Git, using a local repository that already contains the full commit:

```sh
python3 scripts/plugins/build-index.py \
  --repository /path/to/plugins-repo \
  --commit 0123456789abcdef0123456789abcdef01234567 \
  --repository-url https://example.org/owner/plugins \
  --asset-base-url https://example.org/assets \
  --output /path/to/new-output
```

The output directory must not exist; its parent must exist. URLs require HTTPS without user
information; the asset base cannot have a query or fragment. No production URL or key is selected.
The tool reads only committed Git objects under `plugins/<id>/`, ignores working-tree edits, and
never fetches, checks out, signs, uploads, or accesses release credentials. Each directory requires
a JSON object in `plugin.json` with nonempty string `id`, `name`, and `version`. The ID must match
the directory and use lowercase alphanumeric words separated by single hyphens. Unlike local
plugins, catalog plugins require a version; it is a display string, not necessarily SemVer.
Unknown manifest fields are ignored. Duplicate JSON fields, malformed manifests, unsafe paths,
symlinks and submodules fail the build. Paths that alias after Unicode normalization and case
folding are rejected, including file/directory conflicts. At least one plugin directory is required.

Artifacts are `<output>/<commit>/<id>.tar`, with `plugin.json` and assets at each archive's root.
The uncompressed PAX tar stores sorted regular files, Git executable modes (0644 or 0755), zero
mtime/uid/gid, and empty owner/group names. Identical inputs produce identical tar and index bytes.
`<output>/index.json` uses schema 1 and a `plugins` array sorted by ID. Each entry contains `id`,
`version`, `repository`, `commit`, `path`, `archiveURL`, `sha256`, and `size`. The digest and byte
count cover the exact uncompressed tar. JSON uses sorted keys, compact separators, ASCII escapes,
and one final newline, encoded as UTF-8. The index is written last by atomic rename; failures
remove the new output directory. An interrupted process may leave incomplete artifacts without an index.

Publishing and signing are separate operations. A consumer must reject this unsigned index until
a separately supplied detached base64 Ed25519 signature verifies over its exact UTF-8 bytes.
Consumers must reject unknown schemas and ignore unknown fields. This tool does not install
adapters or extract archives, and no production consumer is connected to its output.

Offline tests, using only temporary Git repositories and the standard library:

```sh
python3 -m unittest discover -s scripts/plugins/tests -p "test_*.py"
```
