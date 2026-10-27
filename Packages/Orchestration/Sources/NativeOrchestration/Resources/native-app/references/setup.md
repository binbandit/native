# Native setup and plugin guides

Use `scripts/native setup_status` before setup advice and after a change. It reports Native's build,
agents and sign-in status, durable host, pairing, managed settings and updates. It is read-only and
contains no credentials, transcripts or personal paths. It needs the Native app running.

Use `scripts/native list_skills` to list the available Native guides, then read only the one needed:

```sh
scripts/native get_skill '{"skill":"set-up-native"}' --text
scripts/native get_skill '{"skill":"build-a-native-plugin"}' --text
```

`get_skill` requires `skill`. The returned guide includes the correct plugin directory for this
copy of Native. Read it before writing a plugin or changing setup. Guides switched off by the user
or organization are unavailable through the CLI too.

If a custom shell environment removes Native's session variables, use the per-agent MCP option in
Native's Agents settings. Do not change shell security settings or another task's credentials.
