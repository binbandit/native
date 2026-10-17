#!/usr/bin/env python3
"""Builds V8 150.4.0 from source with its memory sandbox, for `build-script-runtime.sh --sandbox`.

rusty_v8 publishes no prebuilt library with the sandbox, so this builds one: about an hour and
5 GiB of disk, once. Every input is pinned: the v8 crate to the checksum in Cargo.lock, and the two
files the crate leaves out (ICU data and Chromium's vendored Rust crates) to the hashes below. The
result is a gn_out directory (obj/librusty_v8.a and src_binding.rs) that the runtime links against;
the path is printed on success.
"""
import hashlib
import io
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tarfile
import time
import urllib.request
from pathlib import Path

CRATE = Path(__file__).resolve().parents[1]
CACHE = Path(os.environ.get('NATIVE_SCRIPT_RUNTIME_CACHE', Path.home() / 'Library/Caches/Native/ScriptRuntime'))
WORK = CACHE / 'v8-sandbox'
V8_VERSION = '150.4.0'
ICU_COMMIT = 'ee5f27adc28bd3f15b2c293f726d14d2e336cbd5'
ICU_SHA256 = '1cf67874b5a87a8363a86fb3f81e3cbbed54d389062dab8fb52308d5cf8c8612'
RUST_COMMIT = '26e8ff47f18a8d28d6187a04b6a16cb7332356f8'
# Gitiles regenerates archive metadata on every download, so the pin covers each file's path, mode,
# size and contents rather than the archive's bytes.
RUST_TREE_SHA256 = '8fdeda3c0b0a53e1e145014104cb6af00cdd8872de2d3f9e793b3c4e5e5ee536'
MIN_FREE_BYTES = 5 * 1024**3


def tree_sha256(data):
    entries = []
    with tarfile.open(fileobj=io.BytesIO(data)) as archive:
        for member in archive:
            if member.isdir():
                continue
            if not member.isfile():
                raise RuntimeError(f'Unexpected link or special file in archive: {member.name}')
            content = archive.extractfile(member).read()
            entries.append([member.name, member.mode, member.size, hashlib.sha256(content).hexdigest()])
    return hashlib.sha256(json.dumps(sorted(entries), separators=(',', ':')).encode()).hexdigest()


def download(url, destination, expected, digest=lambda data: hashlib.sha256(data).hexdigest(), base64=False):
    if destination.is_file() and digest(destination.read_bytes()) == expected:
        return
    print(f'Downloading {url}', flush=True)
    with urllib.request.urlopen(url, timeout=120) as response:
        data = response.read()
    if base64:
        import base64 as codec
        data = codec.b64decode(data)
    if digest(data) != expected:
        raise RuntimeError(f'Checksum mismatch: {url}')
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(data)


def extract(archive, destination, strip_prefix=''):
    """Extracts regular files only, refusing links and paths that escape `destination`."""
    destination.mkdir(parents=True, exist_ok=True)
    root = destination.resolve()
    count = 0
    with tarfile.open(archive) as tar:
        for member in tar.getmembers():
            name = member.name
            if strip_prefix:
                if not name.startswith(strip_prefix):
                    raise RuntimeError(f'Unexpected path in archive: {name}')
                name = name[len(strip_prefix):]
            if not name or member.isdir():
                continue
            if not member.isfile():
                raise RuntimeError(f'Unexpected link or special file in archive: {name}')
            output = (destination / name).resolve()
            if not output.is_relative_to(root):
                raise RuntimeError(f'Archive path escapes its destination: {name}')
            content = tar.extractfile(member).read()
            if output.exists() and output.read_bytes() != content:
                raise RuntimeError(f'Cached source differs from the pinned archive: {output}')
            if not output.exists():
                output.parent.mkdir(parents=True, exist_ok=True)
                output.write_bytes(content)
                output.chmod(member.mode)
            count += 1
    return count


def locked_v8_checksum():
    lock = (CRATE / 'Cargo.lock').read_text()
    block = next(block for block in lock.split('[[package]]') if re.search(r'^name = "v8"$', block, re.M))
    return re.search(r'^checksum = "([0-9a-f]{64})"$', block, re.M).group(1)


def main():
    WORK.mkdir(parents=True, exist_ok=True)
    if shutil.disk_usage(WORK).free < MIN_FREE_BYTES:
        raise RuntimeError('Building V8 needs at least 5 GiB of free disk space')

    checksum = locked_v8_checksum()
    crate_archive = WORK / f'v8-{V8_VERSION}.crate'
    download(f'https://static.crates.io/crates/v8/v8-{V8_VERSION}.crate', crate_archive, checksum)
    source = WORK / 'v8-source'
    print(f'Verified {extract(crate_archive, source, f"v8-{V8_VERSION}/")} V8 source files', flush=True)
    download(
        f'https://chromium.googlesource.com/chromium/deps/icu.git/+/{ICU_COMMIT}/common/icudtl.dat?format=TEXT',
        source / 'third_party/icu/common/icudtl.dat', ICU_SHA256, base64=True)
    vendor_archive = WORK / 'chromium-crates.tar.gz'
    download(
        f'https://chromium.googlesource.com/chromium/src/third_party/rust/+archive/{RUST_COMMIT}/chromium_crates_io.tar.gz',
        vendor_archive, RUST_TREE_SHA256, digest=tree_sha256)
    print(f'Verified {extract(vendor_archive, source / "third_party/rust/chromium_crates_io")} Chromium Rust files', flush=True)

    # The runtime's own manifest, with only the v8 dependency pointed at the verified source.
    project = WORK / 'project'
    project.mkdir(exist_ok=True)
    manifest = (CRATE / 'Cargo.toml').read_text()
    manifest = manifest.replace('path = "src/main.rs"', f'path = "{CRATE}/src/main.rs"')
    manifest = manifest.replace(f'v8 = {{ version = "={V8_VERSION}",', f'v8 = {{ path = "{source}",')
    manifest = manifest.replace('[package]', f'[package]\nbuild = "{CRATE}/build.rs"', 1)
    (project / 'Cargo.toml').write_text(manifest)
    shutil.copyfile(CRATE / 'Cargo.lock', project / 'Cargo.lock')
    subprocess.run(['cargo', 'metadata', '--offline', '--format-version', '1', '--manifest-path', str(project / 'Cargo.toml')],
                   stdout=subprocess.DEVNULL, check=True)

    target = WORK / 'target'
    environment = {**os.environ, 'V8_FROM_SOURCE': '1', 'CARGO_TARGET_DIR': str(target), 'RUSTC_WRAPPER': ''}
    for name in ['GN_ARGS', 'EXTRA_GN_ARGS', 'CLANG_BASE_PATH', 'RUSTY_V8_ARCHIVE', 'RUSTY_V8_MIRROR', 'RUSTY_V8_SRC_BINDING_PATH']:
        environment.pop(name, None)
    command = ['cargo', 'build', '--release', '--locked', '--features', 'sandbox', '--manifest-path', str(project / 'Cargo.toml')]
    log = WORK / 'build.log'
    print(f'Building V8 with its sandbox; this takes about an hour. Log: {log}', flush=True)
    with log.open('w') as output:
        child = subprocess.Popen(command, env=environment, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            while child.poll() is None:
                if shutil.disk_usage(WORK).free < MIN_FREE_BYTES:
                    raise RuntimeError('Stopped the V8 build to keep 5 GiB of disk free')
                time.sleep(5)
        except BaseException:
            os.killpg(child.pid, signal.SIGTERM)
            child.wait()
            raise
    if child.returncode:
        print(log.read_text()[-12000:], file=sys.stderr)
        return child.returncode
    print(target / 'release/gn_out')
    return 0


if __name__ == '__main__':
    sys.exit(main())
