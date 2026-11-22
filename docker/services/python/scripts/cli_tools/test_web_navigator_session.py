import os
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import web_navigator  # noqa: E402


class SessionChoiceTest(unittest.TestCase):
    """The session named by the caller is used instead of the shared file."""

    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.file = os.path.join(self.dir.name, "session")
        with open(self.file, "w") as f:
            f.write("from-file")
        self.patches = [
            mock.patch.object(web_navigator, "SESSION_FILE", self.file),
            mock.patch.object(web_navigator, "_wd", return_value={"value": "url"}),
        ]
        for p in self.patches:
            p.start()

    def tearDown(self):
        for p in self.patches:
            p.stop()
        web_navigator.REQUESTED_SESSION = None
        web_navigator.MANAGED = False
        self.dir.cleanup()

    def test_a_named_session_wins_over_the_file(self):
        web_navigator.REQUESTED_SESSION = "named"
        self.assertEqual(web_navigator._load_session(), "named")

    def test_without_a_name_the_file_is_used(self):
        self.assertEqual(web_navigator._load_session(), "from-file")

    def test_managed_without_a_name_has_no_session_and_ignores_the_file(self):
        web_navigator.MANAGED = True
        self.assertIsNone(web_navigator._load_session())

    def test_a_named_session_with_another_error_is_still_used(self):
        web_navigator.REQUESTED_SESSION = "named"
        with mock.patch.object(web_navigator, "_wd", return_value={"error": "timeout", "status": 500}):
            self.assertEqual(web_navigator._load_session(), "named")

    def test_a_managed_stop_that_fails_reports_it_and_leaves_the_file(self):
        web_navigator.MANAGED = True
        web_navigator.REQUESTED_SESSION = "named"
        with mock.patch.object(web_navigator, "_wd", return_value={"error": "boom", "status": 500}):
            result = web_navigator.action_stop(None)
        self.assertFalse(result["success"])
        self.assertTrue(os.path.exists(self.file))

    def test_a_managed_stop_of_a_gone_session_counts_as_closed(self):
        web_navigator.MANAGED = True
        web_navigator.REQUESTED_SESSION = "named"
        with mock.patch.object(web_navigator, "_wd",
                               return_value={"error": {"value": {"error": "invalid session id"}}, "status": 404}):
            self.assertTrue(web_navigator.action_stop(None)["success"])
        self.assertTrue(os.path.exists(self.file))

    def test_a_named_session_that_is_gone_is_none_and_leaves_the_file(self):
        web_navigator.REQUESTED_SESSION = "gone"
        with mock.patch.object(web_navigator, "_wd",
                               return_value={"error": {"value": {"error": "invalid session id"}}, "status": 404}):
            self.assertIsNone(web_navigator._load_session())
        self.assertTrue(os.path.exists(self.file))


class GoneTest(unittest.TestCase):
    def test_an_unknown_command_is_not_a_gone_session(self):
        r = {"error": {"value": {"error": "unknown command"}}, "status": 404}
        self.assertFalse(web_navigator._gone(r))

    def test_a_message_naming_an_invalid_session_is_not_enough(self):
        r = {"error": {"value": {"error": "unknown error", "message": "after invalid session id"}}, "status": 500}
        self.assertFalse(web_navigator._gone(r))

    def test_an_invalid_session_id_is_gone(self):
        r = {"error": {"value": {"error": "invalid session id"}}, "status": 404}
        self.assertTrue(web_navigator._gone(r))


class StartTest(unittest.TestCase):
    """A managed start makes one session and never leaves it unreported."""

    def setUp(self):
        self.calls = []
        web_navigator.MANAGED = True

    def tearDown(self):
        web_navigator.MANAGED = False
        web_navigator.REQUESTED_SESSION = None

    def fake_wd(self, fail_on=None, error_on=None):
        def wd(path, method="GET", body=None, timeout=30):
            self.calls.append((method, path))
            if path == "/session" and method == "POST":
                return {"value": {"sessionId": "new"}}
            if fail_on and path.endswith(fail_on):
                raise RuntimeError("navigation failed")
            if error_on and path.endswith(error_on) and method == "POST":
                return {"error": {"value": {"error": "unknown error"}}, "status": 500}
            return {}
        return wd

    def args(self):
        return mock.Mock(url="https://example.com", headless="true")

    def test_a_failure_after_the_session_is_made_closes_it(self):
        with mock.patch.object(web_navigator, "_wd", side_effect=self.fake_wd(fail_on="/url")), \
             mock.patch.object(web_navigator.time, "sleep"):
            result = web_navigator.action_start(self.args())
        self.assertFalse(result["success"])
        self.assertIn(("DELETE", "/session/new"), self.calls)

    def test_a_navigation_webdriver_refuses_closes_the_session(self):
        with mock.patch.object(web_navigator, "_wd", side_effect=self.fake_wd(error_on="/url")), \
             mock.patch.object(web_navigator.time, "sleep"):
            result = web_navigator.action_start(self.args())
        self.assertFalse(result["success"])
        self.assertIn(("DELETE", "/session/new"), self.calls)

    def test_a_managed_start_closes_no_other_session(self):
        web_navigator.REQUESTED_SESSION = "old"
        with mock.patch.object(web_navigator, "_wd", side_effect=self.fake_wd()), \
             mock.patch.object(web_navigator, "_take_screenshot", return_value="s.png"), \
             mock.patch.object(web_navigator, "_get_page_info", return_value={}), \
             mock.patch.object(web_navigator.time, "sleep"):
            result = web_navigator.action_start(self.args())
        self.assertTrue(result["success"])
        self.assertEqual(result["session_id"], "new")
        self.assertFalse([c for c in self.calls if c[0] == "DELETE"])


class StatusTest(unittest.TestCase):
    def test_lists_the_sessions_in_use_and_the_limit(self):
        status = {"value": {"ready": True, "nodes": [{
            "maxSessions": 3,
            "slots": [{"session": {"sessionId": "a"}}, {"session": None}, {"session": {"sessionId": "b"}}]}]}}
        with mock.patch.object(web_navigator, "_wd", return_value=status):
            result = web_navigator.action_status(None)
        self.assertEqual(result, {"success": True, "sessions": ["a", "b"], "max_sessions": 3})

    def test_asks_with_a_short_time_limit(self):
        with mock.patch.object(web_navigator, "_wd", return_value={"value": {"nodes": []}}) as wd:
            web_navigator.action_status(None)
        self.assertEqual(wd.call_args.kwargs.get("timeout"), 5)

    def test_an_unreachable_selenium_is_a_failure(self):
        with mock.patch.object(web_navigator, "_wd", side_effect=ConnectionError("refused")):
            self.assertFalse(web_navigator.action_status(None)["success"])


class WindowTest(unittest.TestCase):
    """A managed action reports the window it acts on now."""

    def tearDown(self):
        web_navigator.MANAGED = False
        web_navigator.REQUESTED_SESSION = None

    def test_an_action_on_a_named_session_reports_its_window(self):
        web_navigator.MANAGED = True
        web_navigator.REQUESTED_SESSION = "s1"
        result = {"success": True}
        with mock.patch.object(web_navigator, "_wd", return_value={"value": "TARGET1"}) as wd:
            web_navigator._add_window("click", result)
        self.assertEqual(result["window"], "TARGET1")
        self.assertEqual(wd.call_args.args[0], "/session/s1/window")

    def test_a_start_reports_the_window_of_the_session_it_made(self):
        web_navigator.MANAGED = True
        result = {"success": True, "session_id": "new"}
        with mock.patch.object(web_navigator, "_wd", return_value={"value": "T"}) as wd:
            web_navigator._add_window("start", result)
        self.assertEqual(wd.call_args.args[0], "/session/new/window")

    def test_a_failed_action_still_reports_the_window(self):
        web_navigator.MANAGED = True
        web_navigator.REQUESTED_SESSION = "s1"
        result = {"success": False}
        with mock.patch.object(web_navigator, "_wd", return_value={"value": "T2"}):
            web_navigator._add_window("click", result)
        self.assertEqual(result["window"], "T2")

    def test_a_window_that_cannot_be_read_is_reported_unknown(self):
        web_navigator.MANAGED = True
        web_navigator.REQUESTED_SESSION = "s1"
        for answer in [OSError("down"), {"value": {"error": "no such window"}, "error": "x"}]:
            result = {"success": True}
            kwargs = {"side_effect": answer} if isinstance(answer, Exception) else {"return_value": answer}
            with mock.patch.object(web_navigator, "_wd", **kwargs):
                web_navigator._add_window("click", result)
            self.assertIn("window", result)
            self.assertIsNone(result["window"])

    def test_nothing_is_added_unmanaged_for_stop_or_without_a_session(self):
        for managed, action, result in [(False, "click", {"success": True}),
                                        (True, "stop", {"success": True}),
                                        (True, "start", {"success": False})]:
            web_navigator.MANAGED = managed
            web_navigator.REQUESTED_SESSION = "s1"
            with mock.patch.object(web_navigator, "_wd", return_value={"value": "T"}):
                web_navigator._add_window(action, result)
            self.assertNotIn("window", result)

if __name__ == "__main__":
    unittest.main()
