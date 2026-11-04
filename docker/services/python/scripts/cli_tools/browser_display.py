"""
How a browser on the Selenium desktop is started, and where it is on screen.

A headless browser is only seen through its screenshots, so it is drawn at a
fixed size and scale for sharp images. A visible browser is seen by a person
through noVNC on the container's desktop, so it fills that desktop at scale 1:
then what the person sees, the page's own coordinates and the screenshots all
match, and the address bar stays on screen.

display_geometry() asks the running browser where it is, rather than assuming
the desktop size: the image's settings can change.
"""

COMMON_ARGS = [
    "--no-sandbox",
    "--disable-dev-shm-usage",
    "--disable-gpu",
]

# Screen, window and page area, in the desktop's pixels.
GEOMETRY_SCRIPT = """
return {
  screen: {width: screen.width, height: screen.height},
  window: {x: window.screenX, y: window.screenY,
           width: window.outerWidth, height: window.outerHeight},
  viewport: {width: window.innerWidth, height: window.innerHeight},
  devicePixelRatio: window.devicePixelRatio
};
"""


def chrome_args(visible, width=1280, height=900, scale=2):
    """Chrome arguments for a visible browser on the desktop, or a headless one
    drawn at width x height and scale."""
    if visible:
        return COMMON_ARGS + [
            "--start-maximized",
            "--window-position=0,0",
            "--force-device-scale-factor=1",
        ]
    return COMMON_ARGS + [
        "--headless=new",
        f"--window-size={width},{height}",
        f"--force-device-scale-factor={scale}",
        "--high-dpi-support=1",
        "--hide-scrollbars",
    ]


def display_geometry(run_js):
    """Where the browser is on the desktop. run_js(script) runs the script in
    the page and returns its value. The page area's origin is placed below the
    browser's own bar (tabs, address bar), which sits at the top of the window.
    Returns None when the browser cannot tell."""
    try:
        g = run_js(GEOMETRY_SCRIPT)
    except Exception:
        return None
    if not isinstance(g, dict):
        return None
    try:
        win, view, scr = g["window"], g["viewport"], g["screen"]
        side = max(0, (win["width"] - view["width"]) // 2)
        viewport_x = win["x"] + side
        viewport_y = win["y"] + max(0, win["height"] - view["height"] - side)
        fits = (win["x"] >= 0 and win["y"] >= 0 and
                win["x"] + win["width"] <= scr["width"] and
                win["y"] + win["height"] <= scr["height"])
    except (KeyError, TypeError):
        return None
    return {
        "screen": scr,
        "window": win,
        "viewport": {"x": viewport_x, "y": viewport_y,
                     "width": view["width"], "height": view["height"]},
        "device_pixel_ratio": g.get("devicePixelRatio"),
        "fits_screen": fits,
    }
