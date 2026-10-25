#!/usr/bin/env python3
"""Build an offline adapter directory using only reviewed lock bytes and local tarballs."""
import argparse
import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import stat
import tempfile

_spec = importlib.util.spec_from_file_location("adapter_lockfile", Path(__file__).with_name("lockfile.py"))
lockfile = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(lockfile)
LIMIT = 256 << 20


def read_local(path):
    path = Path(path).absolute()
    parent = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
    try:
        for component in path.parts[1:-1]:
            if component in (".", ".."):
                raise ValueError("Unsafe path")
            child = os.open(component, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
            os.close(parent)
            parent = child
        fd = os.open(path.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent)
    finally:
        os.close(parent)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_mode & 0o6022 or info.st_nlink != 1 or info.st_size > LIMIT:
            raise ValueError("Unsafe file")
        with os.fdopen(fd, "rb", closefd=False) as stream:
            data = stream.read(LIMIT + 1)
        if len(data) != info.st_size:
            raise ValueError("Changed file")
        return data
    finally:
        os.close(fd)


def relative(path):
    return (isinstance(path, str) and path and "\\" not in path
            and all(ord(c) >= 32 for c in path)
            and all(part not in ("", ".", "..") for part in path.split("/")))


def supports(values, target):
    return values is None or ("!" + target not in values
                             and (target in values or "any" in values or all(v.startswith("!") for v in values)))


def build(pair, archives, output, *, adapter, version, os_name, architecture,
          node_version, npm_version, agent_version, entry):
    if not relative(entry) or not entry.startswith("node_modules/"):
        raise ValueError("Invalid entry")
    pair, archives, output = map(Path, (pair, archives, output))
    package, lock = (read_local(pair / name) for name in ("package.json", "package-lock.json"))
    # Audit a stable snapshot, not an independently reopened source pair.
    with tempfile.TemporaryDirectory(prefix="offline-adapter-audit-") as temporary:
        scratch = Path(temporary)
        (scratch / "package.json").write_bytes(package)
        (scratch / "package-lock.json").write_bytes(lock)
        lockfile.audit(scratch, adapter, version)
    payloads = {"package.json": package, "package-lock.json": lock}
    required = {entry}
    for path, record in json.loads(lock)["packages"].items():
        if not path:
            continue
        digest = base64.b64decode(record["integrity"][7:], validate=True).hex()
        # Include every locked archive, including alternate-platform optionals. No cache metadata,
        # registry indexes, npm configuration or credentials are copied from the administrator.
        data = read_local(archives / (digest + ".tgz"))
        if hashlib.sha512(data).hexdigest() != digest:
            raise ValueError("Archive integrity mismatch")
        payloads[f"cache/_cacache/content-v2/sha512/{digest[:2]}/{digest[2:4]}/{digest[4:]}"] = data
        if supports(record.get("os"), os_name) and supports(record.get("cpu"), architecture):
            required.add(path + "/package.json")
    if sum(map(len, payloads.values())) > LIMIT:
        raise ValueError("Bundle too large")
    manifest = {
        "formatVersion": 1, "adapterID": adapter, "adapterVersion": version,
        "os": os_name, "architecture": architecture, "nodeVersion": node_version,
        "npmVersion": npm_version, "agentVersion": agent_version, "entryPoint": entry,
        "requiredInstalledFiles": sorted(required),
        "payloads": [{"path": path, "size": len(data), "sha256": hashlib.sha256(data).hexdigest()}
                     for path, data in sorted(payloads.items())],
    }
    payloads["bundle.json"] = (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode()
    # Reserve the output exclusively. Failure removes only the directory this operation created.
    output.mkdir(mode=0o700)
    try:
        for path, data in payloads.items():
            target = output / path
            # The importer rejects group- or world-writable directories, so set each level's
            # mode explicitly: mkdir(parents=True) leaves intermediates to the ambient umask.
            directory = output
            for part in Path(path).parent.parts:
                directory = directory / part
                if not directory.is_dir():
                    directory.mkdir(mode=0o700)
                    directory.chmod(0o700)
            with target.open("xb") as stream:
                stream.write(data)
            target.chmod(0o600)
    except BaseException:
        shutil.rmtree(output)
        raise
    return hashlib.sha256(payloads["bundle.json"]).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pair", type=Path)
    parser.add_argument("archives", type=Path)
    parser.add_argument("output", type=Path)
    for option in ("adapter", "version", "node-version", "npm-version", "agent-version", "entry"):
        parser.add_argument("--" + option, required=True)
    parser.add_argument("--os", dest="os_name", choices=("darwin", "linux"), required=True)
    parser.add_argument("--architecture", choices=("arm64", "x64"), required=True)
    args = vars(parser.parse_args())
    try:
        digest = build(**args)
    except (OSError, ValueError, KeyError, TypeError):
        parser.exit(1, "Offline bundle failed: check reviewed inputs and local artifacts.\n")
    print("Manifest SHA-256 (requires independent deployment approval): " + digest)


if __name__ == "__main__":
    main()
