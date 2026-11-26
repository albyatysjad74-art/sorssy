import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROCESSOR = ROOT / ".github" / "scripts" / "process-sorssy-request.py"
OWNER = "albyatysjad74-art"


class ProcessorAuthorizationTests(unittest.TestCase):
    def run_request(self, sender: str) -> tuple[str, dict]:
        with tempfile.TemporaryDirectory() as temp:
            repo = Path(temp)
            (repo / ".github" / "scripts").mkdir(parents=True)
            shutil.copy2(PROCESSOR, repo / ".github" / "scripts" / "process-sorssy-request.py")
            (repo / "iQsign-Apps-Source.json").write_text(
                json.dumps({"name": "test", "apps": []}), encoding="utf-8"
            )
            (repo / "sorssy-sources.json").write_text(
                json.dumps({"sources": []}), encoding="utf-8"
            )
            payload = {
                "action": "add_app",
                "name": "Sample App",
                "bundleIdentifier": "com.example.sample",
                "version": "1.0",
                "category": "أدوات",
                "iconURL": "https://example.com/icon.png",
                "downloadURL": "https://example.com/sample.ipa",
            }
            event = {
                "issue": {
                    "title": "[Sorssy] إضافة تطبيق: Sample App",
                    "user": {"login": OWNER},
                    "body": json.dumps(payload, ensure_ascii=False),
                },
                "sender": {"login": sender},
            }
            event_path = repo / "event.json"
            output_path = repo / "github-output.txt"
            event_path.write_text(json.dumps(event, ensure_ascii=False), encoding="utf-8")
            env = os.environ.copy()
            env["EVENT_PATH"] = str(event_path)
            env["GITHUB_OUTPUT"] = str(output_path)
            result = subprocess.run(
                ["python3", ".github/scripts/process-sorssy-request.py"],
                cwd=repo,
                env=env,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            outputs = dict(
                line.split("=", 1)
                for line in output_path.read_text(encoding="utf-8").splitlines()
            )
            updated_source = json.loads((repo / "iQsign-Apps-Source.json").read_text(encoding="utf-8"))
            return outputs["status"], updated_source

    def test_non_owner_editor_cannot_change_owner_issue(self):
        status, source = self.run_request("someone-else")
        self.assertEqual(status, "invalid")
        self.assertEqual(source["apps"], [])

    def test_owner_can_submit_app(self):
        status, source = self.run_request(OWNER)
        self.assertEqual(status, "added")
        self.assertEqual(source["apps"][0]["name"], "Sample App")


if __name__ == "__main__":
    unittest.main()
