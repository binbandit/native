#!/usr/bin/env python3
"""Build unsigned catalog artifacts from local Git objects, without a checkout."""

import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
from urllib.parse import urlsplit


def require(condition, message):
    if not condition:
        raise ValueError(message)


def https_url(value):
    url = urlsplit(value)
    require(url.scheme == "https" and url.hostname and url.username is None
            and url.password is None and "\\" not in value
            and not any(c.isspace() or ord(c) < 32 for c in value), "expected HTTPS URL without user information")
    url.port  # Validate malformed ports too.
    return url


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, f"duplicate JSON field: {key}")
        result[key] = value
    return result


def build(args):
    require(re.fullmatch(r"[0-9a-f]{40}", args.commit), "commit must be 40 lowercase hex characters")
    https_url(args.repository_url)
    base = https_url(args.asset_base_url)
    require(not base.query and not base.fragment, "asset base URL cannot contain a query or fragment")
    # Disable replacement objects and lazy fetching, including on older Git versions.
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    env.update(GIT_NO_LAZY_FETCH="1", GIT_TERMINAL_PROMPT="0", GIT_ALLOW_PROTOCOL="")

    def git(*argv):
        return subprocess.run(["git", "--no-replace-objects", "-c", "protocol.allow=never",
                               "-C", str(args.repository), *argv], env=env, check=True,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout

    require(git("cat-file", "-t", args.commit).strip() == b"commit", "object is not a commit")
    plugins = {}
    for record in git("ls-tree", "--full-tree", "-r", "-t", "-z", args.commit, "--", "plugins").split(b"\0"):
        if not record:
            continue
        header, raw_path = record.split(b"\t", 1)
        mode, kind, oid = header.decode("ascii").split()
        path = raw_path.decode("utf-8")
        parts = path.split("/")
        require(all(p not in ("", ".", "..") for p in parts) and "\\" not in path
                and not any(ord(c) < 32 or ord(c) == 127 for c in path), f"unsafe path: {path!r}")
        require((mode, kind) in (("040000", "tree"), ("100644", "blob"), ("100755", "blob")),
                f"not a regular file or directory: {path}")
        if len(parts) == 1:
            require(kind == "tree", "plugins must be a directory")
        elif len(parts) == 2 and kind == "tree":
            require(re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", parts[1]), f"invalid plugin ID: {parts[1]}")
            require(parts[1] not in plugins, f"duplicate plugin directory: {path}")
            plugins[parts[1]] = []
        elif len(parts) > 2 and kind == "blob":
            plugins[parts[1]].append(("/".join(parts[2:]), mode, oid))
    require(plugins, "commit contains no plugin directories")
    args.output.mkdir()  # Exclusive creation: never clean up a pre-existing destination.
    try:
        folder = args.output / args.commit
        folder.mkdir()
        entries = []
        for plugin_id, files in sorted(plugins.items()):
            require(len({path for path, _, _ in files}) == len(files), f"{plugin_id}: duplicate file paths")
            manifests = [oid for path, _, oid in files if path == "plugin.json"]
            require(len(manifests) == 1, f"{plugin_id}: expected one plugin.json")
            manifest = json.loads(git("cat-file", "blob", manifests[0]).decode("utf-8"),
                                  object_pairs_hook=unique_object,
                                  parse_constant=lambda value: require(False, f"invalid JSON constant: {value}"))
            require(isinstance(manifest, dict), f"{plugin_id}: manifest must be an object")
            for field in ("id", "name", "version"):
                value = manifest.get(field)
                require(isinstance(value, str) and value.strip(), f"{plugin_id}: invalid {field}")
                value.encode("utf-8")
            require(manifest["id"] == plugin_id, f"{plugin_id}: duplicate or mismatched manifest ID")
            archive = folder / f"{plugin_id}.tar"
            with tarfile.open(archive, "w", format=tarfile.PAX_FORMAT) as tar:
                for path, mode, oid in sorted(files):
                    blob = git("cat-file", "blob", oid)
                    info = tarfile.TarInfo(path)
                    info.size, info.mode = len(blob), int(mode, 8) & 0o777
                    info.mtime = info.uid = info.gid = 0
                    info.uname = info.gname = ""
                    tar.addfile(info, io.BytesIO(blob))
            digest = hashlib.sha256()
            with archive.open("rb") as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(chunk)
            entries.append(dict(id=plugin_id, version=manifest["version"], repository=args.repository_url,
                                commit=args.commit, path=f"plugins/{plugin_id}",
                                archiveURL=f"{args.asset_base_url.rstrip('/')}/{args.commit}/{plugin_id}.tar",
                                sha256=digest.hexdigest(), size=archive.stat().st_size))
        data = json.dumps(dict(schema=1, plugins=entries), sort_keys=True, separators=(",", ":")) + "\n"
        temporary = args.output / ".index.json.tmp"
        temporary.write_bytes(data.encode("utf-8"))
        temporary.rename(args.output / "index.json")
    except BaseException:
        shutil.rmtree(args.output)
        raise


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", required=True, type=Path)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--repository-url", required=True)
    parser.add_argument("--asset-base-url", required=True)
    parser.add_argument("--output", required=True, type=Path)
    try:
        build(parser.parse_args())
    except (ValueError, OSError, subprocess.CalledProcessError, tarfile.TarError) as error:
        parser.exit(1, f"error: {error}\n")
