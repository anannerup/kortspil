"""The dashboard's stop/start button (tools/esmakker_dashboard/server.py):
stop writes the run's STOP file, start refuses while the learner is alive.
No training is started: subprocess.Popen is replaced."""

import importlib.util
import json
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request
from pathlib import Path
from unittest import mock

SERVER = Path(__file__).resolve().parents[2] / "esmakker_dashboard" / "server.py"
spec = importlib.util.spec_from_file_location("esmakker_dashboard_server", SERVER)
server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server)


def write_status(run_dir, state="running", age=1.0):
    (run_dir / "status.json").write_text(json.dumps({"state": state, "heartbeat": time.time() - age}))


class StateTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.runs = Path(self.tmp.name)
        self.run = self.runs / "night"
        self.run.mkdir()
        (self.run / "config.json").write_text("{}")

    def test_running_stopping_stopped(self):
        self.assertEqual("stopped", server.training_state(self.run))  # no status yet
        write_status(self.run)
        self.assertEqual("running", server.training_state(self.run))
        write_status(self.run, age=server.STALE_SECONDS + 5)  # a learner that died without a word
        self.assertEqual("stopped", server.training_state(self.run))
        write_status(self.run)
        (self.run / "STOP").write_text("")
        self.assertEqual("stopping", server.training_state(self.run))
        write_status(self.run, state="stopped")
        self.assertEqual("stopped", server.training_state(self.run))

    def test_stop_writes_the_stop_file_only_when_running(self):
        self.assertFalse(server.request_stop(self.run))
        self.assertFalse((self.run / "STOP").exists())
        write_status(self.run)
        self.assertTrue(server.request_stop(self.run))
        self.assertTrue((self.run / "STOP").exists())

    def test_start_is_refused_while_running_and_for_a_run_that_does_not_exist(self):
        trainer = server.Trainer(self.runs, "night")
        write_status(self.run)
        with mock.patch.object(server.subprocess, "Popen") as popen:
            self.assertFalse(trainer.start()["ok"])
            popen.assert_not_called()
            self.assertFalse(server.Trainer(self.runs, "nothing").start()["ok"])
            popen.assert_not_called()

    def test_start_resumes_the_run_with_its_own_settings(self):
        trainer = server.Trainer(self.runs, "night")
        write_status(self.run, state="stopped")
        with mock.patch.object(server.subprocess, "Popen") as popen:
            out = trainer.start()
            self.assertTrue(out["ok"])
            command = popen.call_args[0][0]
            self.assertEqual(["-m", "esmakker_ai.train", "start", "--runs-dir", str(self.runs), "--run", "night"],
                             command[1:])
            self.assertEqual("starting", trainer.state())  # until its first heartbeat
            self.assertFalse(trainer.start()["ok"])  # a second click does not start a second learner
            self.assertEqual(1, popen.call_count)


class HttpTest(unittest.TestCase):
    def test_the_button_needs_the_pages_header_and_the_server_is_local(self):
        with tempfile.TemporaryDirectory() as tmp:
            runs = Path(tmp)
            run = runs / "night"
            run.mkdir()
            (run / "config.json").write_text("{}")
            write_status(run)
            httpd = server.make_server(run, None, server.Trainer(runs, "night"), 0)
            self.assertEqual("127.0.0.1", httpd.server_address[0])
            threading.Thread(target=httpd.serve_forever, daemon=True).start()
            self.addCleanup(httpd.shutdown)
            base = f"http://127.0.0.1:{httpd.server_address[1]}"

            def post(path, headers):
                request = urllib.request.Request(base + path, data=b"", method="POST", headers=headers)
                try:
                    with urllib.request.urlopen(request, timeout=10) as r:
                        return r.status, json.loads(r.read())
                except urllib.error.HTTPError as e:
                    return e.code, json.loads(e.read())

            self.assertEqual(403, post("/api/stop", {})[0])
            self.assertFalse((run / "STOP").exists())
            status, out = post("/api/stop", {"X-Esmakker": "1"})
            self.assertEqual(200, status)
            self.assertTrue(out["ok"])
            self.assertTrue((run / "STOP").exists())
            with urllib.request.urlopen(base + "/api/data", timeout=30) as r:
                data = json.loads(r.read())
            self.assertEqual("stopping", data["training"])
            self.assertEqual([], data["ladder"])


if __name__ == "__main__":
    unittest.main()
