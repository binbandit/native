#!/usr/bin/env python3
"""Maintainer-only npm lockfile generation and offline auditing."""
import argparse
import base64
import json
import re
import subprocess
import tempfile
from pathlib import Path
from urllib.parse import urlsplit

NAME = r"(?:@[a-z0-9][a-z0-9._-]*/)?[a-z0-9][a-z0-9._-]*"
NUMBER = r"(?:0|[1-9][0-9]*)"
PRE = rf"(?:{NUMBER}|[0-9]*[A-Za-z-][0-9A-Za-z-]*)"
VERSION = rf"{NUMBER}\.{NUMBER}\.{NUMBER}(?:-{PRE}(?:\.{PRE})*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"


class AuditError(ValueError):
    """Safe diagnostic without registry credentials or npm output."""


def require(condition, message):
    if not condition:
        raise AuditError(message)


def matches(pattern, value):
    return isinstance(value, str) and re.fullmatch(pattern, value) is not None


def https(value):
    try:
        url = urlsplit(value) if isinstance(value, str) else None
        return (url is not None and url.scheme == "https" and url.hostname
                and url.port != 0 and url.username is None and url.password is None
                and not url.query and not url.fragment and not re.search(r"[\s\\]", value))
    except ValueError:
        return False


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def audit(directory, package, version):
    require(matches(NAME, package) and matches(VERSION, version), "Expected a package name and exact SemVer")
    pin = {package: version}
    manifest, lock = (read_json(directory / name) for name in ("package.json", "package-lock.json"))
    require(isinstance(lock, dict) and type(lock.get("lockfileVersion")) is int
            and lock["lockfileVersion"] == 3, "Only lockfileVersion 3 is supported")
    packages = lock.get("packages")
    require(isinstance(packages, dict) and isinstance(packages.get(""), dict), "Missing root package")
    for root in (manifest, packages[""]):
        require(isinstance(root, dict) and root.get("dependencies") == pin, "Root pin mismatch")
        require(not any(root.get(key) for key in ("devDependencies", "optionalDependencies", "peerDependencies")),
                "Unexpected root dependencies")
    adapter = packages.get("node_modules/" + package)
    require(isinstance(adapter, dict) and adapter.get("version") == version, "Adapter resolution mismatch")
    for path, record in packages.items():
        require(isinstance(record, dict) and "link" not in record, "Links or invalid package records")
        for key in ("dependencies", "optionalDependencies", "peerDependencies"):
            dependencies = record.get(key, {})
            require(isinstance(dependencies, dict), "Invalid dependency metadata")
            require(all(matches(NAME, name) and matches(rf"(?:npm:{NAME}@)?[^/:\x00-\x1f\\]*", spec)
                        and not spec.strip().startswith(".") for name, spec in dependencies.items()),
                    "Only registry dependency specifications are supported")
        if not path:
            continue
        require(matches(rf"node_modules/{NAME}(?:/node_modules/{NAME})*", path), "Unsupported package path")
        require(matches(VERSION, record.get("version")), "Package version must be exact SemVer")
        resolved = record.get("resolved")
        require(https(resolved) and urlsplit(resolved).path.strip("/"), "Expected an HTTPS tarball URL")
        integrity = record.get("integrity")
        require(matches(r"sha512-[A-Za-z0-9+/]{86}==", integrity), "Expected a sha512 integrity digest")
        digest = base64.b64decode(integrity[7:], validate=True)
        require(len(digest) == 64 and base64.b64encode(digest).decode() == integrity[7:],
                "Invalid sha512 integrity digest")


def generate(directory, package, version, registry):
    require(matches(NAME, package) and matches(VERSION, version), "Expected a package name and exact SemVer")
    require(https(registry), "Registry must be HTTPS without credentials, query or fragment")
    directory.mkdir()  # Refuse even an empty existing output directory.
    # Only publish audited files. npm failures (even after writing a lock) leave no usable output.
    with tempfile.TemporaryDirectory(prefix=".resolve-", dir=directory) as scratch:
        stage = Path(scratch).resolve()
        (stage / "package.json").write_text(
            json.dumps({"name": "native-adapter-lock", "private": True,
                        "dependencies": {package: version}}, indent=2) + "\n", encoding="utf-8")
        argv = ["npm", "install", "--package-lock-only", "--ignore-scripts", "--no-audit", "--no-fund",
                "--lockfile-version=3", "--global=false", "--prefix", str(stage), "--cache", str(stage / ".npm"),
                "--registry", registry]
        if package.startswith("@"):
            argv.append(f"--{package.split('/')[0]}:registry={registry}")
        subprocess.run(argv, cwd=stage, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        audit(stage, package, version)
        for name in ("package.json", "package-lock.json"):
            (stage / name).replace(directory / name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="mode", required=True)
    for mode in ("generate", "check"):
        command = commands.add_parser(mode)
        command.add_argument("package")
        command.add_argument("version")
        command.add_argument("directory", type=Path)
        if mode == "generate":
            command.add_argument("--registry", default="https://registry.npmjs.org/")
    args = parser.parse_args()
    try:
        if args.mode == "generate":
            generate(args.directory, args.package, args.version, args.registry)
        else:
            audit(args.directory, args.package, args.version)
    except AuditError as error:
        parser.exit(1, f"Lockfile audit failed: {error}.\n")
    except (OSError, ValueError, subprocess.CalledProcessError):
        # npm output and exception text can contain credentials from registry configuration.
        parser.exit(1, "Lockfile operation failed: check inputs, file schema and npm availability.\n")
    print("Lockfile audit passed.")


if __name__ == "__main__":
    main()
