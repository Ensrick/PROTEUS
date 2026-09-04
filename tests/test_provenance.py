from __future__ import annotations

import hashlib
import json
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]


class ProvenanceTests(unittest.TestCase):
    def test_version_is_consistent(self) -> None:
        version = (REPOSITORY_ROOT / "VERSION").read_text(encoding="utf-8").strip()
        provenance = json.loads(
            (REPOSITORY_ROOT / "PROVENANCE.json").read_text(encoding="utf-8")
        )
        self.assertEqual(version, provenance["version"])

    def test_patched_source_matches_dependency_lock(self) -> None:
        source = (REPOSITORY_ROOT / "ProteusMCMScript.psc").read_bytes()
        actual = hashlib.sha256(source).hexdigest().upper()
        dependency_lock = json.loads(
            (REPOSITORY_ROOT / "dependencies.lock.json").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual(actual, dependency_lock["expected"]["patchedSourceSha256"])


if __name__ == "__main__":
    unittest.main()
