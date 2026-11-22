import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import browser_display  # noqa: E402


def page(window, viewport, screen=(1920, 1080), dpr=1):
    """A run_js stand-in answering what a page would report."""
    def run_js(_script):
        return {
            "screen": {"width": screen[0], "height": screen[1]},
            "window": dict(zip(("x", "y", "width", "height"), window)),
            "viewport": dict(zip(("width", "height"), viewport)),
            "devicePixelRatio": dpr,
        }
    return run_js


class ChromeArgsTest(unittest.TestCase):
    def test_visible_fills_the_desktop_at_scale_one(self):
        args = browser_display.chrome_args(visible=True)
        self.assertIn("--start-maximized", args)
        self.assertIn("--force-device-scale-factor=1", args)
        self.assertNotIn("--headless=new", args)
        self.assertFalse(any(a.startswith("--window-size=") for a in args))

    def test_headless_draws_at_the_given_size_and_scale(self):
        args = browser_display.chrome_args(visible=False, width=1280, height=900, scale=2)
        self.assertIn("--headless=new", args)
        self.assertIn("--window-size=1280,900", args)
        self.assertIn("--force-device-scale-factor=2", args)


class DisplayGeometryTest(unittest.TestCase):
    def test_a_maximized_window_fits_and_the_page_sits_below_the_browser_bar(self):
        g = browser_display.display_geometry(page((0, 0, 1920, 1080), (1920, 990)))
        self.assertTrue(g["fits_screen"])
        self.assertEqual(g["viewport"], {"x": 0, "y": 90, "width": 1920, "height": 990})
        self.assertEqual(g["device_pixel_ratio"], 1)

    def test_a_window_larger_than_the_desktop_does_not_fit(self):
        g = browser_display.display_geometry(page((0, 0, 2560, 1800), (2560, 1710), dpr=2))
        self.assertFalse(g["fits_screen"])

    def test_a_browser_that_cannot_tell_gives_none(self):
        def failing(_script):
            raise RuntimeError("no session")
        self.assertIsNone(browser_display.display_geometry(failing))
        self.assertIsNone(browser_display.display_geometry(lambda _s: None))
        self.assertIsNone(browser_display.display_geometry(lambda _s: {"window": {}}))


if __name__ == "__main__":
    unittest.main()
