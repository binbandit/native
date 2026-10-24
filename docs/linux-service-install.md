# Installing the Linux user service

Run `scripts/host/install-user-service.py` with Python 3 as the intended Linux
service user, after installing a compatible host binary and its dependencies.
It uses [the existing renderer](linux-user-service.md) unchanged. Review first:

```sh
python3 scripts/host/install-user-service.py \
  --executable /home/alex/.native/bin/native-host \
  --state-directory /home/alex/.local/state/native-host --dry-run
```

Remove `--dry-run` to install and reload the user manager. Add `--enable-now`
only when ready to enable and start the host. Without it, the installer runs only
`systemctl --user daemon-reload`; it does not start the host. Dry-run validates
the inputs and reports the target and command argv as JSON, without writes or
subprocesses. The host executable is checked but never executed by the installer.
With `--enable-now`, after reload a read-only `systemctl --user show` checks that
the manager's `FragmentPath` names the installed file before enabling it. A missing
or higher-priority conflicting unit prevents activation and is left untouched.
Dry-run lists this query but cannot establish which file the manager will select.

The destination is always `systemd/user/native-host.service` under an absolute
`--config-home`, otherwise absolute `XDG_CONFIG_HOME`, otherwise `~/.config`.
Relative or empty XDG values are ignored. An override must also be where the
user manager looks for units. Symlinks anywhere in the destination path and
`..` in the config base are refused. The binary and state paths must satisfy the
renderer; the binary must exist and be executable. Use a dedicated private state
directory with room for `/host.sock` within Linux's 107-byte socket path limit.
The installer does not create the state directory; the host owns that step.

A new unit is published atomically with mode 0600, without overwriting anything.
An identical regular unit is accepted unchanged, so a failed reload can be retried.
A different unit or a symlink is refused. Exit 0 means the requested steps completed
(or dry-run passed); 2 means invalid CLI syntax; 1 means validation, filesystem or
systemctl failure. Errors name the last completed stage. Reload failure prevents
enable; enable failure may have partially enabled or started the service. The unit
is retained in both cases. Fix the reported cause, then explicitly rerun the same
command. No rollback or unrelated-file cleanup is attempted.

Inspect with `systemctl --user status native-host.service`. For manual removal,
first verify the installed file is yours, run `systemctl --user disable --now
native-host.service`, remove only the reported unit file, then run `systemctl
--user daemon-reload`. Keep the binary and state unless separately retiring them.
Lingering is an administrator choice affecting all user services; see the
[renderer guide](linux-user-service.md). The installer never invokes sudo or
loginctl, changes lingering or power settings, downloads binaries, or uses a shell.

Offline checks: `python3 -m unittest discover -s scripts/host/tests -p
'test_install_user_service.py'` and the same command with `test_systemd_unit.py`.
Fixtures prove CLI, filesystem and subprocess behavior, not a live systemd boot,
logout, crash recovery or reboot. Linux gateway, update support and Add Host
provisioning remain separate work; this installer does not make Linux a finished droid.
