"""Exercise the pack command against a local LFS remote, without release credentials."""

import base64
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(os.environ.get("CELEBRATION_PACK_SCRIPT", Path(__file__).resolve().parents[1] / "celebration-assets.sh"))
PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
)


class CelebrationPackagingTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="celebration-icons-test-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name) / "source"
        self.root.mkdir()
        self.git("init", "-q")
        self.git("config", "user.name", "Test")
        self.git("config", "user.email", "test@example.invalid")
        self.git("lfs", "install", "--local")
        (self.root / ".gitattributes").write_text("design/**/*.png filter=lfs diff=lfs merge=lfs -text\n")
        scripts = self.root / "scripts/release"
        scripts.mkdir(parents=True)
        shutil.copy2(SCRIPT, scripts / SCRIPT.name)
        self.edition = self.root / "design/app-icon/celebrations/valentines-day"
        self.edition.mkdir(parents=True)
        for channel in ("stable", "beta", "nightly", "dev"):
            for appearance in ("light", "dark"):
                (self.edition / f"{channel}-{appearance}.png").write_bytes(PNG)
        self.git("add", ".")
        self.git("-c", "commit.gpgsign=false", "commit", "-qm", "test: artwork")
        self.output = Path(self.directory.name) / "packs"
        self.signer = Path(self.directory.name) / "sign"
        self.signer.write_text('#!/bin/sh\nprintf "test-signature"\n')
        self.signer.chmod(0o755)

    def git(self, *args, root=None, **kwargs):
        return subprocess.check_output(
            ["git", "-C", str(root or self.root), *args], stderr=subprocess.PIPE, **kwargs
        )

    def pack(self, root=None):
        return subprocess.run(
            ["bash", str((root or self.root) / "scripts/release" / SCRIPT.name),
             "pack", str(self.output), "test"],
            env={**os.environ, "CELEBRATION_ASSETS_SIGN": str(self.signer)},
            capture_output=True, text=True,
        )

    def assert_valid_pack(self):
        data = (self.output / "celebration-valentines-day.json").read_bytes()
        pack = json.loads(data)
        self.assertEqual(len(pack["images"]), 8)
        self.assertTrue(all(base64.b64decode(image) == PNG for image in pack["images"].values()))
        index = json.loads((self.output / "celebration-assets.json").read_bytes())
        self.assertEqual(index["packs"]["valentines-day"]["sha256"], hashlib.sha256(data).hexdigest())
        self.assertEqual(index["packs"]["valentines-day"]["size"], len(data))

    def test_materialized_artwork_needs_no_remote(self):
        result = self.pack()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_valid_pack()

    def test_pointer_checkout_downloads_real_images_from_its_configured_remote(self):
        remote = Path(self.directory.name) / "remote.git"
        subprocess.run(["git", "init", "--bare", "-q", str(remote)], check=True)
        self.git("remote", "add", "origin", str(remote))
        self.git("push", "-q", "origin", "HEAD:refs/heads/main")
        checkout = Path(self.directory.name) / "checkout"
        subprocess.run(
            ["git", "clone", "-q", "--branch", "main", str(remote), str(checkout)],
            env={**os.environ, "GIT_LFS_SKIP_SMUDGE": "1"}, check=True,
        )
        pointer = checkout / self.edition.relative_to(self.root) / "stable-light.png"
        self.assertTrue(pointer.read_bytes().startswith(b"version https://git-lfs.github.com/spec/v1"))
        result = self.pack(checkout)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_valid_pack()

    def test_unavailable_lfs_objects_never_get_signed(self):
        pointer = self.git("show", "HEAD:design/app-icon/celebrations/valentines-day/stable-light.png")
        (self.edition / "stable-light.png").write_bytes(pointer)
        shutil.rmtree(self.root / ".git/lfs/objects")
        result = self.pack()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.output / "celebration-assets.json.sig").exists())

    def test_invalid_png_never_gets_signed(self):
        (self.edition / "stable-light.png").write_bytes(b"not an image")
        result = self.pack()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("stable-light.png", result.stderr)
        self.assertFalse((self.output / "celebration-assets.json.sig").exists())


if __name__ == "__main__":
    unittest.main()
