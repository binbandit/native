# Linux system information

The existing `_native/host/status` API reports the Linux distribution in `system` through
`HostSystemInfo.portable`. It reads UTF-8 `/etc/os-release`, falling back to `/usr/lib/os-release`
only if the first file is missing or unreadable. The files are never combined. A readable empty
or malformed file does not cause a read of the other file.

Only `PRETTY_NAME`, `NAME` and `VERSION` are parsed. A nonempty `PRETTY_NAME` wins; otherwise
`NAME` and a nonempty `VERSION` are joined with a space. `NAME` alone is sufficient. Without a
usable name, the existing Foundation operating-system string is retained.

The parser follows the [os-release format](https://www.freedesktop.org/software/systemd/man/latest/os-release.html):
blank and comment lines are ignored, whitespace around assignments is accepted, and values can be
unquoted, single quoted or double quoted with shell-style backslash escaping. Variables and command
expressions remain literal text; no file is sourced and no command runs. Malformed assignments
(including unclosed or concatenated quotes) are ignored. Empty or whitespace-only values are
unusable; later valid assignments replace earlier ones for the same key.

Verification on macOS exercises the same parser using Ubuntu, Debian and Alpine-shaped fixtures,
malformed values, quoting, escaping and injected file reads for precedence and failures:

```sh
nice -n 10 swift test -j 4 --package-path Packages/NativeHost --filter LinuxSystemInfoTests
```

The existing Linux CI runs the suite on x86_64 and arm64. The Linux-only expectation compares
`HostSystemInfo.portable` with the runner's os-release files; an in-process client also reads
`_native/host/status`. macOS retains its existing system information, and portable hosts retain
`model = nil` and live load-average sampling. This change does not alter the wire format,
Settings > Hosts, host configuration or doctor output. No GUI verification is required.
