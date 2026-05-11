import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "ingest_memory.py"


def run_ingest(project: Path, text: str):
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--project", str(project), "--text", text],
        text=True,
        capture_output=True,
        check=True,
    )
    return json.loads(result.stdout)


def write_node(path: Path, node_id: str, tags: str, body: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        f"""---
id: {node_id}
type: module
status: in-progress
updated: 2026-05-11
summary: "{node_id} summary"
depends_on: []
auto_linked: []
tags: [{tags}]
aliases: []
---

# {node_id}

## Current State
{body}

## Key Decisions
None.

## Cross-Module Connection Points
None.

## Open Issues
None.

## Change Log
- [2026-05-11] Initial fixture
""",
        encoding="utf-8",
    )


class IngestMemoryTests(unittest.TestCase):
    def test_login_note_targets_existing_login_node_and_extracts_endpoint(self):
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp)
            write_node(project / "meta" / "feat_login.md", "feat_login", "login, auth, frontend", "Login page exists.")
            write_node(project / "meta" / "mod_auth-api.md", "mod_auth-api", "auth, api", "POST /api/v1/auth/login returns tokens.")

            proposal = run_ingest(
                project,
                "登录页面已经接好了，调用 POST /api/v1/auth/login。成功后保存 access_token 和 refresh_token。后端返回 expires_in: 900。",
            )

            self.assertEqual(proposal["version"], 1)
            self.assertEqual(proposal["target_node"], "meta/feat_login.md")
            self.assertIn("POST /api/v1/auth/login", proposal["extracted"]["api_endpoints"])
            self.assertIn("access_token", proposal["extracted"]["fields"])
            self.assertIn("refresh_token", proposal["extracted"]["fields"])
            self.assertEqual(proposal["edge_candidates"][0]["from"], "meta/feat_login.md")
            self.assertEqual(proposal["edge_candidates"][0]["to"], "meta/mod_auth-api.md")
            self.assertGreaterEqual(proposal["edge_candidates"][0]["confidence"], 8.0)
            self.assertIn("exact endpoint match", proposal["edge_candidates"][0]["evidence"][0])

    def test_unknown_topic_proposes_new_feature_node(self):
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp)
            (project / "meta").mkdir(parents=True)

            proposal = run_ingest(project, "新增仪表盘页面 /dashboard，包含 MetricCard 和 ActivityFeed 两个组件。")

            self.assertEqual(proposal["target_node"], "meta/feat_dashboard.md")
            self.assertEqual(proposal["action"], "create_node")
            self.assertIn("dashboard", proposal["suggested_frontmatter"]["tags"])
            self.assertIn("MetricCard", proposal["extracted"]["components"])
            self.assertIn("ActivityFeed", proposal["extracted"]["components"])


if __name__ == "__main__":
    unittest.main()
