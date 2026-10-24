#!/usr/bin/env python3
"""Install the rendered Linux user unit for an already-installed native-host."""

import sys

sys.dont_write_bytecode = True  # Dry-run must not create import caches.

import argparse
from contextlib import contextmanager
import importlib.util
import json
import os
from pathlib import Path
import stat
import subprocess
import uuid


def renderer():
    spec = importlib.util.spec_from_file_location(
        "systemd_unit", Path(__file__).with_name("render-systemd-unit.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@contextmanager
def destination(directory, create):
    # Walk by descriptor so a substituted symlink cannot redirect a later write.
    descriptor = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in directory.parts[1:]:
            if create:
                try:
                    os.mkdir(part, mode=0o700, dir_fd=descriptor)
                except FileExistsError:
                    pass
            try:
                child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=descriptor)
            except FileNotFoundError:
                if create:
                    raise
                yield None
                return
            os.close(descriptor)
            descriptor = child
        yield descriptor
    finally:
        os.close(descriptor)


def identical(descriptor, name, unit):
    try:
        file = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=descriptor)
    except FileNotFoundError:
        return False
    with os.fdopen(file, "rb") as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode) or stream.read(len(unit) + 1) != unit:
            raise ValueError("refusing an existing different or non-regular unit")
    return True


def publish(descriptor, name, unit):
    temporary = ".native-host-" + uuid.uuid4().hex
    file = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600, dir_fd=descriptor)
    try:
        with os.fdopen(file, "wb") as stream:
            stream.write(unit)
            stream.flush()
            os.fsync(stream.fileno())
        # A hard link publishes complete bytes atomically and never replaces a rival file.
        try:
            os.link(temporary, name, src_dir_fd=descriptor, dst_dir_fd=descriptor, follow_symlinks=False)
        except FileExistsError:
            if not identical(descriptor, name, unit):
                raise
        os.fsync(descriptor)
    finally:
        os.unlink(temporary, dir_fd=descriptor)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--executable", required=True)
    parser.add_argument("--state-directory", required=True)
    parser.add_argument("--config-home", help="absolute config base (otherwise XDG_CONFIG_HOME or ~/.config)")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--enable-now", action="store_true")
    args = parser.parse_args(argv)
    stage = "no unit installation confirmed; no systemctl commands run"
    try:
        render = renderer()
        unit = render.render(args.executable, args.state_directory).encode("utf-8")
        if not Path(args.executable).is_file() or not os.access(args.executable, os.X_OK):
            raise ValueError("executable must be an installed, executable regular file")
        state = Path(args.state_directory)
        if state.exists() and not state.is_dir():
            raise ValueError("state directory is not a directory")
        xdg = os.environ.get("XDG_CONFIG_HOME", "")
        config = args.config_home if args.config_home is not None else (
            xdg if xdg.startswith("/") else str(Path.home() / ".config"))
        base = Path(render.absolute_path(config))
        if ".." in base.parts:
            raise ValueError("config home must not contain '..'")
        target = base / "systemd/user/native-host.service"
        commands = [["systemctl", "--user", "daemon-reload"]]
        if args.enable_now:
            commands.append(["systemctl", "--user", "enable", "--now", target.name])
        with destination(target.parent, create=not args.dry_run) as descriptor:
            exists = descriptor is not None and identical(descriptor, target.name, unit)
            if args.dry_run:
                print(json.dumps({"target": str(target), "argv": commands}))
                return 0
            if not exists:
                publish(descriptor, target.name, unit)
        stage = f"unit installed or identical at {target}; daemon-reload not completed"
        for command in commands:
            subprocess.run(command, check=True)
            stage = f"unit retained at {target}; {' '.join(command)} completed"
        print(stage)
        return 0
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"{error}\nCompleted stage: {stage}. Fix the cause and rerun the same command; "
              "no unit is removed or rolled back.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
