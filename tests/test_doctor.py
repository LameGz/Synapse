import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "doctor.sh"


def write_node(path: Path, body: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(body, encoding="utf-8")


class DoctorTests(unittest.TestCase):
    def test_reports_healthy_project(self):
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp)
            write_node(
                project / "meta" / "mod_auth-api.md",
                """---
id: mod_auth-api
type: module
status: stable
updated: 2026-05-11
summary: "Auth API"
depends_on: []
auto_linked: []
tags: [auth, api]
aliases: []
---

# Auth API

## Current State
POST /api/v1/auth/login returns tokens.

## Key Decisions
None.

## Cross-Module Connection Points
None.

## Open Issues
None.

## Change Log
- [2026-05-11] Initial
""",
            )

            result = subprocess.run(
                ["bash", str(SCRIPT), "--project", str(project)],
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertIn("Synapse doctor: OK", result.stdout)

    def test_reports_dead_auto_link(self):
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp)
            write_node(
                project / "meta" / "feat_login.md",
                """---
id: feat_login
type: feature
status: in-progress
updated: 2026-05-11
summary: "Login"
depends_on: []
auto_linked:
  - meta/missing.md
tags: [login]
aliases: []
---

# Login

## Current State
- Login page exists.

## Key Decisions
None.

## Cross-Module Connection Points
None.

## Open Issues
None.

## Change Log
- [2026-05-11] Initial
""",
            )

            result = subprocess.run(
                ["bash", str(SCRIPT), "--project", str(project)],
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("DEAD AUTO_LINKED", result.stdout)
            self.assertIn("meta/missing.md", result.stdout)


if __name__ == "__main__":
    unittest.main()
