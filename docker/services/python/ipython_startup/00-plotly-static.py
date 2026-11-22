# A Plotly chart shown in a notebook is saved with a PNG beside its
# interactive form, so a viewer that runs no scripts (the work screen) shows
# it. Only when kaleido is installed (Install Options: Plotly static images);
# it draws the PNG with Debian's Chromium.
import importlib.util
import os

if importlib.util.find_spec("kaleido") and importlib.util.find_spec("plotly"):
    if os.path.exists("/usr/bin/chromium"):
        os.environ.setdefault("BROWSER_PATH", "/usr/bin/chromium")
    import plotly.io as _pio

    _pio.renderers.default = "notebook+png"
    del _pio
