import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "apply_memory_proposal.py"


def run_apply(project: Path, proposal: dict):
    proposal_file = project / "proposal.json"
    proposal_file.write_text(json.dumps(proposal, ensure_ascii=False), encoding="utf-8")
    subprocess.run([sys.executable, str(SCRIPT), "--project", str(project), "--proposal", str(proposal_file)], check=True)


class ApplyMemoryProposalTests(unittest.TestCase):
    def test_creates_node_and_adds_auto_linked_edge(self):
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp)
            (project / "meta").mkdir()
            (project / "meta" / "mod_auth-api.md").write_text("""---
id: mod_auth-api
type: module
status: stable
updated: 2026-05-11
summary: "Auth API"
depends_on: []
auto_linked: []
tags: [auth, api]
aliases: [login]
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
""", encoding="utf-8")
            proposal = {
                "version": 1,
                "action": "create_node",
                "target_node": "meta/feat_login.md",
                "suggested_frontmatter": {
                    "id": "feat_login",
                    "type": "feature",
                    "status": "in-progress",
                    "updated": "2026-05-11",
                    "summary": "Login feature",
                    "depends_on": [],
                    "auto_linked": [],
                    "tags": ["login", "auth"],
                    "aliases": [],
                },
                "node_update": {
                    "current_state_bullets": ["登录页面调用 POST /api/v1/auth/login。"],
                    "change_log_entry": {
                        "date": "2026-05-11",
                        "context": "Natural-language memory ingestion",
                        "change": "登录页面调用 POST /api/v1/auth/login。",
                        "impact": "Updates project memory graph context",
                        "affected": "meta/feat_login.md",
                    },
                },
                "edge_candidates": [
                    {
                        "from": "meta/feat_login.md",
                        "to": "meta/mod_auth-api.md",
                        "confidence": 9.0,
                        "evidence": ["exact endpoint match: POST /api/v1/auth/login"],
                        "apply_to": "auto_linked",
                    }
                ],
            }

            run_apply(project, proposal)

            text = (project / "meta" / "feat_login.md").read_text(encoding="utf-8")
            self.assertIn("id: feat_login", text)
            self.assertIn("登录页面调用 POST /api/v1/auth/login。", text)
            self.assertIn("auto_linked:", text)
            self.assertIn("- meta/mod_auth-api.md", text)
            self.assertIn("exact endpoint match", text)

    def test_updates_existing_node_without_duplicate_bullets(self):
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp)
            (project / "meta").mkdir()
            node = project / "meta" / "feat_login.md"
            node.write_text("""---
id: feat_login
type: feature
status: in-progress
updated: 2026-05-10
summary: "Login"
depends_on: []
auto_linked: []
tags: [login]
aliases: []
---

# Login

## Current State
- Existing state.

## Key Decisions
None.

## Cross-Module Connection Points
None.

## Open Issues
None.

## Change Log
- [2026-05-10] Initial
""", encoding="utf-8")
            proposal = {
                "version": 1,
                "action": "update_node",
                "target_node": "meta/feat_login.md",
                "suggested_frontmatter": {},
                "node_update": {
                    "current_state_bullets": ["Existing state.", "Stores refresh_token."],
                    "change_log_entry": {
                        "date": "2026-05-11",
                        "context": "Natural-language memory ingestion",
                        "change": "Stores refresh_token.",
                        "impact": "Updates project memory graph context",
                        "affected": "meta/feat_login.md",
                    },
                },
                "edge_candidates": [],
            }

            run_apply(project, proposal)

            text = node.read_text(encoding="utf-8")
            self.assertEqual(text.count("Existing state."), 1)
            self.assertIn("- Stores refresh_token.", text)
            self.assertIn("**Context**: Natural-language memory ingestion", text)


if __name__ == "__main__":
    unittest.main()
