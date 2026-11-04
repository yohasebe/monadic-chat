import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import web_navigator  # noqa: E402


class SessionErrorTest(unittest.TestCase):
    def test_a_full_queue_is_told_as_no_free_browser(self):
        r = {"error": {"value": {"error": "session not created",
                                  "message": "New session request timed out"}}, "status": 500}
        self.assertIn("No browser is free right now", web_navigator._session_error(r))

    def test_another_failure_keeps_its_text(self):
        r = {"error": {"value": {"error": "session not created",
                                  "message": "Chrome failed to start"}}, "status": 500}
        message = web_navigator._session_error(r)
        self.assertTrue(message.startswith("Failed to create session:"))
        self.assertIn("Chrome failed to start", message)


if __name__ == "__main__":
    unittest.main()
