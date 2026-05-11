import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "generate_memory_map.sh"


def write_node(path: Path, text: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


class GenerateMemoryMapTests(unittest.TestCase):
    def test_json_includes_effective_edges_from_depends_on_and_auto_linked(self):
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp)
            scripts = project / "scripts"
            scripts.mkdir()
            shutil.copy2(SCRIPT, scripts / "generate_memory_map.sh")

            write_node(
                project / "meta" / "mod_project.md",
                """---
id: mod_project
type: module
status: stable
updated: 2026-05-11
summary: "Project"
depends_on: []
auto_linked: []
tags: [project]
aliases: []
---

# Project

## Current State
Project root.

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
            write_node(
                project / "meta" / "feat_login.md",
                """---
id: feat_login
type: feature
status: in-progress
updated: 2026-05-11
summary: "Login"
depends_on:
  - meta/mod_project.md
auto_linked:
  - meta/mod_auth-api.md
tags: [login, auth]
aliases: []
---

# Login

## Current State
- Login calls POST /api/v1/auth/login.

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
                ["bash", (scripts / "generate_memory_map.sh").as_posix(), "--full"],
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            map_text = (project / "MEMORY_MAP.md").read_text(encoding="utf-8")
            self.assertIn("effective_edges: meta/mod_project.md, meta/mod_auth-api.md", map_text)

            data = json.loads((project / "MEMORY_MAP.json").read_text(encoding="utf-8"))
            login = next(node for node in data["nodes"] if node["id"] == "feat_login")
            self.assertEqual(login["depends_on"], ["meta/mod_project.md"])
            self.assertEqual(login["auto_linked"], ["meta/mod_auth-api.md"])
            self.assertEqual(login["effective_edges"], ["meta/mod_project.md", "meta/mod_auth-api.md"])


if __name__ == "__main__":
    unittest.main()
