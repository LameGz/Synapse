import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = (ROOT / "scripts" / "suggest_edges.sh").as_posix()


class SuggestEdgesTests(unittest.TestCase):
    def test_proposal_mode_prints_explainable_edges(self):
        with tempfile.TemporaryDirectory() as tmp:
            proposal = {
                "version": 1,
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
            proposal_file = Path(tmp) / "proposal.json"
            proposal_file.write_text(json.dumps(proposal, ensure_ascii=False), encoding="utf-8")

            result = subprocess.run(
                ["bash", SCRIPT, "--proposal", proposal_file.as_posix()],
                text=True,
                capture_output=True,
                check=False,
                cwd=ROOT,
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)

            self.assertIn("Synapse Proposal Edge Suggestions", result.stdout)
            self.assertIn("meta/feat_login.md -> meta/mod_auth-api.md", result.stdout)
            self.assertIn("Confidence: 9.0/10", result.stdout)
            self.assertIn("exact endpoint match: POST /api/v1/auth/login", result.stdout)
            self.assertIn("[AUTO] Apply to auto_linked", result.stdout)


if __name__ == "__main__":
    unittest.main()
