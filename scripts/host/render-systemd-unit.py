#!/usr/bin/env python3
"""Render a user unit for a preinstalled host; never inspect or change services."""

import argparse
import posixpath
import sys


def absolute_path(value):
    if not value.startswith("/") or posixpath.normpath(value) in ("/", "//"):
        raise ValueError("paths must be absolute and must not name the filesystem root")
    if any(ord(char) < 32 or ord(char) == 127 for char in value):
        raise ValueError("paths must not contain control characters (including NUL or newlines)")
    return value


def quote(value):
    # systemd.syntax C escapes and systemd specifiers are independent of shell quoting.
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"').replace("%", "%%") + '"'


def render(executable, state_directory):
    executable = absolute_path(executable)
    state_directory = absolute_path(state_directory)
    # systemd rejects these in the executable even after decoding valid C escapes.
    if executable.endswith("/") or any(char in executable for char in "\"'\\"):
        raise ValueError("executable must not end in / or contain quotes or backslashes")
    # ':' disables dollar expansion for every argument, without introducing a shell.
    return f"""[Unit]
Description=Native host

[Service]
Type=simple
ExecStart=:{quote(executable)} serve --home {quote(state_directory)}
Restart=on-failure
RestartSec=3s
UMask=0077
KillMode=control-group

[Install]
WantedBy=default.target
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--executable", required=True, help="absolute Linux native-host path")
    parser.add_argument("--state-directory", required=True, help="absolute private host state path")
    arguments = parser.parse_args()
    try:
        unit = render(arguments.executable, arguments.state_directory)
    except ValueError as error:
        parser.error(str(error))
    sys.stdout.write(unit)


if __name__ == "__main__":
    main()
