# Linux host user service

`scripts/host/render-systemd-unit.py` prints a `native-host.service` for an already
installed Linux host. Python 3's standard library is sufficient. Rendering only
writes stdout: it does not inspect services, create directories, install binaries,
download anything, or change systemd. No production consumer calls it yet.

Provide explicit absolute Linux paths, even when rendering on macOS. Paths are
not resolved or checked for existence. The state directory must belong to the
service user and be dedicated to this host: it holds `host.sock`, `host.lock`,
`host.sqlite` and credentials. The host makes it mode 0700. Keep its path short
enough for Linux's Unix socket limit (107 bytes including `/host.sock`).

The unit runs `native-host serve --home <directory>` directly, without a shell
or `--inherit-environment`; the host captures its login-shell environment.
Quoted arguments preserve spaces, quotes and backslashes, `%%` preserves literal
percent signs, and the `:` command prefix disables dollar expansion. Systemd
itself forbids quotes and backslashes in executable filenames, so those are
rejected (use a compatible installed path). Control characters, relative paths,
filesystem roots, and executable paths ending in `/` are also rejected.

## Manual installation on Linux

Run as the intended service user, after installing a compatible executable and
its runtime dependencies. Replace these example paths with your own. First render
to a temporary file and inspect it:

```sh
unit=$(mktemp)
python3 scripts/host/render-systemd-unit.py \
  --executable /home/alex/.native/bin/native-host \
  --state-directory /home/alex/.local/state/native-host > "$unit"
cat "$unit"
```

After reviewing it, install and start it manually. Check for an existing
`native-host.service` first; back it up and review any overrides before replacing
it. Do not run two hosts against the same state directory.

```sh
mkdir -p "$HOME/.config/systemd/user"
install -m 0600 "$unit" "$HOME/.config/systemd/user/native-host.service"
rm "$unit"
systemctl --user daemon-reload
systemctl --user enable --now native-host.service
systemctl --user status native-host.service
journalctl --user -u native-host.service
```

`Restart=on-failure` retries crashes and exit 75 (the host's restart request)
after 3 seconds, subject to systemd's normal start limits. Exit 0 stays stopped.
`UMask=0077` keeps new files private; `KillMode=control-group` cleans up child
processes when the service stops. `WantedBy=default.target` starts it with the
user manager. This alone does not promise operation after logout or reboot.

Lingering is a separate administrator decision: an administrator may authorize
`loginctl enable-linger alex` to start that user's manager at boot and retain it
after logout. The renderer never invokes loginctl or sudo. Lingering affects all
of that user's services; do not disable it merely because this unit is removed.

To remove the service manually (state and the preinstalled binary are retained):

```sh
systemctl --user disable --now native-host.service
rm "$HOME/.config/systemd/user/native-host.service"
systemctl --user daemon-reload
```

## Validation and limits

Run `python3 -m unittest discover -s scripts/host/tests -p "test_systemd_unit.py"`.
Portable tests cover the CLI, exact fields, exit-75 policy, escaping and invalid
paths. On Linux, a required parser test runs `systemd-analyze --user verify` with
scratch units and a symlink to an existing harmless executable. It checks decoded
arguments without starting any service. Run the command on Ubuntu 24.04 for real
parser evidence; a missing parser fails on Linux. On macOS the parser test is
explicitly skipped, not counted as verified. Linux validation is required before
calling the rendered unit verified.

This does not install or build the host, pair a device, implement keep-awake,
add doctor checks, or make Linux a finished droid. Add Host and the existing Linux
build workflow remain separate. No unit should be applied on elara for testing.
