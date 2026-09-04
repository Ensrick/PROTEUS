from __future__ import annotations

import re
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
MCM_SOURCE = REPOSITORY_ROOT / "ProteusMCMScript.psc"

EXPECTED_BRANCHES = {
    "castK1": "k1",
    "castK3": "k3",
    "castK5": "k5",
    "castK6": "k6",
    "castK7": "k7",
    "castK8": "k8",
    "castK9": "k9",
    "castK10": "k10",
    "castK11": "k11",
    "castK12": "k12",
    "castK13": "k13",
    "castK14": "k14",
}


def active_source(text: str) -> str:
    """Remove Papyrus comment-only lines before structural checks."""
    return "\n".join(
        line for line in text.splitlines() if not line.lstrip().startswith(";")
    )


def function_body(text: str, function_name: str) -> str:
    match = re.search(
        rf"(?ims)^\s*function\s+{re.escape(function_name)}\b.*?^\s*endFunction\s*$",
        text,
    )
    if match is None:
        raise AssertionError(f"Function not found: {function_name}")
    return match.group(0)


class ProteusMcmHotkeyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = MCM_SOURCE.read_text(encoding="utf-8-sig")
        cls.body = function_body(active_source(cls.source), "OnOptionKeyMapChange")

    def test_state_option_api_is_absent(self) -> None:
        self.assertNotIn("SetKeyMapOptionValueST", self.source)

    def test_exactly_twelve_active_indexed_updates_exist(self) -> None:
        calls = re.findall(
            r"\bself\.SetKeyMapOptionValue\(option,\s*keyCode,\s*false\)",
            self.body,
        )
        self.assertEqual(len(calls), len(EXPECTED_BRANCHES))

    def test_every_active_hotkey_branch_updates_its_index_and_global(self) -> None:
        branches = list(
            re.finditer(
                r"(?im)^\s*(?:if|elseif)\s+option\s*==\s*(castK\d+)\s*$",
                self.body,
            )
        )
        self.assertEqual(
            {match.group(1) for match in branches}, set(EXPECTED_BRANCHES)
        )

        for index, match in enumerate(branches):
            option_name = match.group(1)
            branch_end = (
                branches[index + 1].start()
                if index + 1 < len(branches)
                else self.body.lower().rfind("endfunction")
            )
            branch = self.body[match.end() : branch_end]

            with self.subTest(option=option_name):
                self.assertEqual(
                    branch.count(
                        "self.SetKeyMapOptionValue(option, keyCode, false)"
                    ),
                    1,
                )
                target_global = EXPECTED_BRANCHES[option_name]
                self.assertRegex(
                    branch,
                    rf"(?i)\b{re.escape(target_global)}\.setValue\(keyCode as Float\)",
                )


if __name__ == "__main__":
    unittest.main()
