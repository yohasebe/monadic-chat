#!/usr/bin/env python3
"""
Interactive Web Navigator - W3C WebDriver HTTP API client
Controls a non-headless Chrome browser via Selenium Grid for interactive web browsing.
Session ID is persisted to allow multiple tool calls to share the same browser session.
"""

import argparse
import base64
import json
import os
import sys
import time

import requests

WEBDRIVER_URL = "http://selenium_service:4444"
SESSION_FILE = "/monadic/data/.browser_session_id"
SCREENSHOT_DIR = "/monadic/data"
VIEWPORT_WIDTH = 1280
VIEWPORT_HEIGHT = 900


def _wd(path, method="GET", body=None):
    """Send a request to WebDriver and return parsed JSON."""
    url = f"{WEBDRIVER_URL}{path}"
    headers = {"Content-Type": "application/json"}
    resp = requests.request(method, url, headers=headers,
                            json=body, timeout=30)
    if resp.status_code >= 400:
        try:
            err = resp.json()
        except Exception:
            err = resp.text
        return {"error": err, "status": resp.status_code}
    if not resp.text.strip():
        return {}
    return resp.json()


def _save_session(session_id):
    """Persist session ID to file."""
    with open(SESSION_FILE, "w") as f:
        f.write(session_id)


def _load_session():
    """Load session ID from file, return None if missing or session is dead."""
    if not os.path.exists(SESSION_FILE):
        return None
    with open(SESSION_FILE, "r") as f:
        sid = f.read().strip()
    if not sid:
        return None
    # Verify the session is still alive
    r = _wd(f"/session/{sid}/url")
    if "error" in r:
        _clear_session()
        return None
    return sid


def _clear_session():
    """Remove persisted session file."""
    if os.path.exists(SESSION_FILE):
        os.remove(SESSION_FILE)


def _take_screenshot(session_id):
    """Take a screenshot and save it to the shared folder. Returns filename."""
    r = _wd(f"/session/{session_id}/screenshot")
    if "error" in r:
        return None
    img_data = base64.b64decode(r["value"])
    timestamp = int(time.time() * 1000)
    filename = f"browser_{timestamp}.png"
    filepath = os.path.join(SCREENSHOT_DIR, filename)
    with open(filepath, "wb") as f:
        f.write(img_data)
    return filename


def _execute_js(session_id, script, args=None):
    """Execute JavaScript in the browser and return the result."""
    body = {"script": script, "args": args or []}
    r = _wd(f"/session/{session_id}/execute/sync", method="POST", body=body)
    return r


def _get_page_info(session_id):
    """Get page title, URL, and list of interactive elements."""
    # Get current URL
    url_r = _wd(f"/session/{session_id}/url")
    current_url = url_r.get("value", "")

    # Get page title
    title_r = _wd(f"/session/{session_id}/title")
    title = title_r.get("value", "")

    # Get interactive elements via JavaScript
    js = """
    var selectors = 'a[href], button, input, select, textarea, [role="button"], [onclick]';
    var elems = document.querySelectorAll(selectors);
    var results = [];
    var seen = new Set();
    var vpW = window.innerWidth, vpH = window.innerHeight;
    for (var i = 0; i < elems.length && results.length < 50; i++) {
        var el = elems[i];
        // Skip hidden elements
        var style = window.getComputedStyle(el);
        if (style.display === 'none' || style.visibility === 'hidden' ||
            el.offsetWidth === 0 || el.offsetHeight === 0) continue;

        var tag = el.tagName.toLowerCase();
        var type = el.getAttribute('type') || '';
        var text = (el.innerText || el.value || el.getAttribute('aria-label') ||
                    el.getAttribute('title') || el.getAttribute('placeholder') || '').trim();
        if (text.length > 80) text = text.substring(0, 80) + '...';
        var href = el.getAttribute('href') || '';
        var ariaLabel = el.getAttribute('aria-label') || '';

        // Detect semantic region by walking up ancestors
        var region = '';
        var ancestor = el;
        for (var r = 0; r < 6 && ancestor; r++) {
            var atag = ancestor.tagName ? ancestor.tagName.toLowerCase() : '';
            if (atag === 'header' || atag === 'nav' || atag === 'main' ||
                atag === 'footer' || atag === 'aside') {
                region = atag;
                break;
            }
            var role = ancestor.getAttribute ? (ancestor.getAttribute('role') || '') : '';
            if (role === 'banner') { region = 'header'; break; }
            if (role === 'navigation') { region = 'nav'; break; }
            if (role === 'main') { region = 'main'; break; }
            if (role === 'contentinfo') { region = 'footer'; break; }
            if (role === 'complementary') { region = 'aside'; break; }
            ancestor = ancestor.parentElement;
        }

        // Check if element is in viewport
        var rect = el.getBoundingClientRect();
        var inViewport = (rect.top < vpH && rect.bottom > 0 &&
                          rect.left < vpW && rect.right > 0);

        // Build CSS selector with priority:
        // id > name > data-testid > aria-label > data-action/data-target/data-toggle > nth-of-type (3-level ancestor)
        var css = '';
        if (el.id) {
            css = '#' + CSS.escape(el.id);
        } else if (el.getAttribute('name')) {
            css = tag + '[name="' + el.getAttribute('name') + '"]';
        } else if (el.getAttribute('data-testid')) {
            css = '[data-testid="' + el.getAttribute('data-testid') + '"]';
        } else if (el.getAttribute('aria-label')) {
            var alVal = el.getAttribute('aria-label').replace(/'/g, "\\'");
            css = tag + "[aria-label='" + alVal + "']";
        } else if (el.getAttribute('data-action')) {
            css = tag + '[data-action="' + el.getAttribute('data-action') + '"]';
        } else if (el.getAttribute('data-target')) {
            css = tag + '[data-target="' + el.getAttribute('data-target') + '"]';
        } else if (el.getAttribute('data-toggle')) {
            css = tag + '[data-toggle="' + el.getAttribute('data-toggle') + '"]';
        } else {
            // Use nth-of-type with up to 3 ancestor levels for uniqueness
            var parts = [];
            var node = el;
            for (var lvl = 0; lvl < 3 && node && node.parentElement; lvl++) {
                var parent = node.parentElement;
                var ntag = node.tagName.toLowerCase();
                var siblings = Array.from(parent.children).filter(function(c) {
                    return c.tagName === node.tagName;
                });
                var idx = siblings.indexOf(node) + 1;
                var seg = ntag + ':nth-of-type(' + idx + ')';
                // Use id or class of ancestor to anchor
                if (parent.id) {
                    parts.unshift(seg);
                    parts.unshift('#' + CSS.escape(parent.id));
                    break;
                }
                parts.unshift(seg);
                node = parent;
            }
            css = parts.join(' > ');
        }

        // Verify selector uniqueness
        if (!css) css = tag;
        try {
            var matches = document.querySelectorAll(css);
            if (matches.length > 1) {
                // Disambiguate by appending nth-of-type from parent
                var p = el.parentElement;
                if (p) {
                    var sibs = Array.from(p.children).filter(function(c) { return c.tagName === el.tagName; });
                    var sidx = sibs.indexOf(el) + 1;
                    css = css + ':nth-of-type(' + sidx + ')';
                }
            }
        } catch(e) { /* ignore selector errors */ }

        // Avoid duplicates
        if (seen.has(css)) continue;
        seen.add(css);

        var obj = {
            tag: tag,
            type: type,
            text: text,
            href: href,
            selector: css
        };
        if (region) obj.region = region;
        if (ariaLabel) obj.aria_label = ariaLabel;
        obj.in_viewport = inViewport;

        results.push(obj);
    }
    return results;
    """
    elements_r = _execute_js(session_id, js)
    elements = elements_r.get("value", [])

    return {
        "url": current_url,
        "title": title,
        "interactive_elements": elements
    }


def action_start(args):
    """Start a new browser session (non-headless) and navigate to URL."""
    # Close any existing session first
    old_sid = _load_session()
    if old_sid:
        _wd(f"/session/{old_sid}", method="DELETE")
        _clear_session()

    # Create new session - non-headless so user can watch via noVNC
    caps = {
        "capabilities": {
            "alwaysMatch": {
                "browserName": "chrome",
                "goog:chromeOptions": {
                    "args": [
                        "--no-sandbox",
                        "--disable-dev-shm-usage",
                        "--disable-gpu",
                        f"--window-size={VIEWPORT_WIDTH},{VIEWPORT_HEIGHT}",
                        "--force-device-scale-factor=2",
                        "--high-dpi-support=1"
                    ]
                }
            }
        }
    }

    r = _wd("/session", method="POST", body=caps)
    if "error" in r:
        return {"success": False, "error": f"Failed to create session: {r['error']}"}

    session_id = r["value"]["sessionId"]
    _save_session(session_id)

    # Navigate to URL
    url = args.url or "about:blank"
    _wd(f"/session/{session_id}/url", method="POST", body={"url": url})

    # Wait for page load
    time.sleep(2)

    # Take screenshot and get page info
    screenshot = _take_screenshot(session_id)
    page_info = _get_page_info(session_id)

    return {
        "success": True,
        "session_id": session_id,
        "screenshot": screenshot,
        "page_info": page_info,
        "novnc_url": "http://localhost:7900"
    }


def action_navigate(args):
    """Navigate to a URL in the existing session."""
    session_id = _load_session()
    if not session_id:
        return {"success": False, "error": "No active browser session. Use --action start first."}

    _wd(f"/session/{session_id}/url", method="POST", body={"url": args.url})
    time.sleep(2)

    screenshot = _take_screenshot(session_id)
    page_info = _get_page_info(session_id)

    return {
        "success": True,
        "screenshot": screenshot,
        "page_info": page_info
    }


def _get_window_handles(session_id):
    """Get all window handles for the session."""
    r = _wd(f"/session/{session_id}/window/handles")
    return r.get("value", [])


def _switch_to_window(session_id, handle):
    """Switch to a specific window/tab."""
    _wd(f"/session/{session_id}/window", method="POST", body={"handle": handle})


def _handle_new_tab(session_id, handles_before):
    """If a new tab opened after an action, switch to it.
    Returns True if switched to a new tab, False otherwise."""
    handles_after = _get_window_handles(session_id)
    new_handles = [h for h in handles_after if h not in handles_before]
    if new_handles:
        _switch_to_window(session_id, new_handles[-1])
        return True
    return False


def action_click(args):
    """Click an element using JavaScript for reliability.
    Automatically detects and switches to new tabs opened by the click."""
    session_id = _load_session()
    if not session_id:
        return {"success": False, "error": "No active browser session. Use --action start first."}

    # Record window handles before click to detect new tabs
    handles_before = _get_window_handles(session_id)

    selector = args.selector
    js = """
    var el = document.querySelector(arguments[0]);
    if (!el) return {found: false};
    // Scroll into view
    el.scrollIntoView({behavior: 'smooth', block: 'center'});
    // Small delay for smooth scroll
    return new Promise(function(resolve) {
        setTimeout(function() {
            el.click();
            resolve({found: true, tag: el.tagName, text: (el.innerText || '').substring(0, 50)});
        }, 300);
    });
    """
    r = _execute_js(session_id, js, [selector])

    if "error" in r:
        return {"success": False, "error": f"Click failed: {r['error']}"}

    result = r.get("value", {})
    if not result or not result.get("found"):
        return {"success": False, "error": f"Element not found: {selector}"}

    time.sleep(1)

    # Detect and switch to new tab if one was opened (e.g., target="_blank" links)
    switched = _handle_new_tab(session_id, handles_before)

    if switched:
        # Extra wait for the new tab to finish loading
        time.sleep(1)

    screenshot = _take_screenshot(session_id)
    page_info = _get_page_info(session_id)

    response = {
        "success": True,
        "clicked": result,
        "screenshot": screenshot,
        "page_info": page_info
    }

    if switched:
        response["tab_switched"] = True
        response["message"] = "Clicked element opened a new tab; automatically switched to it."

    return response


def action_type(args):
    """Type text into an input element."""
    session_id = _load_session()
    if not session_id:
        return {"success": False, "error": "No active browser session. Use --action start first."}

    selector = args.selector
    text = args.text

    js = """
    var el = document.querySelector(arguments[0]);
    if (!el) return {found: false};
    el.scrollIntoView({behavior: 'smooth', block: 'center'});
    el.focus();
    el.value = '';
    el.value = arguments[1];
    // Dispatch events to trigger frameworks
    el.dispatchEvent(new Event('input', {bubbles: true}));
    el.dispatchEvent(new Event('change', {bubbles: true}));
    return {found: true, tag: el.tagName, value: el.value.substring(0, 50)};
    """
    r = _execute_js(session_id, js, [selector, text])

    if "error" in r:
        return {"success": False, "error": f"Type failed: {r['error']}"}

    result = r.get("value", {})
    if not result or not result.get("found"):
        return {"success": False, "error": f"Element not found: {selector}"}

    time.sleep(0.5)
    screenshot = _take_screenshot(session_id)
    page_info = _get_page_info(session_id)

    return {
        "success": True,
        "typed": result,
        "screenshot": screenshot,
        "page_info": page_info
    }


def action_screenshot(args):
    """Take a screenshot of the current page."""
    session_id = _load_session()
    if not session_id:
        return {"success": False, "error": "No active browser session. Use --action start first."}

    screenshot = _take_screenshot(session_id)
    if not screenshot:
        return {"success": False, "error": "Failed to take screenshot."}

    return {
        "success": True,
        "screenshot": screenshot
    }


def action_get_page_info(args):
    """Get page title, URL, and interactive elements."""
    session_id = _load_session()
    if not session_id:
        return {"success": False, "error": "No active browser session. Use --action start first."}

    page_info = _get_page_info(session_id)

    return {
        "success": True,
        "page_info": page_info
    }


def action_full_screenshot(args):
    """Take a full-page screenshot. For tall content, captures overlapping tiles."""
    session_id = _load_session()
    if not session_id:
        return {"success": False, "error": "No active browser session. Use --action start first."}

    # Get actual content dimensions
    dims_js = """return {
        w: Math.max(document.documentElement.scrollWidth, document.body.scrollWidth, window.innerWidth),
        h: Math.max(document.documentElement.scrollHeight, document.body.scrollHeight, window.innerHeight)
    }"""
    dims_result = _execute_js(session_id, dims_js)
    dims = dims_result.get("value", {})
    content_w = dims.get("w", VIEWPORT_WIDTH)
    content_h = dims.get("h", VIEWPORT_HEIGHT)

    # Threshold: if content fits in ~1.5 viewports, resize and capture as single image
    # Beyond that, use tiled capture for better Vision API resolution
    max_single_height = int(VIEWPORT_HEIGHT * 1.5)  # 1350px logical

    if content_h <= max_single_height:
        # Single image mode: resize viewport to fit content
        capped_w = min(content_w, 4000)
        capped_h = min(content_h, 4000)
        resize_body = {"width": capped_w + 40, "height": capped_h + 40}
        _wd(f"/session/{session_id}/window/rect", method="POST", body=resize_body)
        time.sleep(1)
        _execute_js(session_id, "window.scrollTo(0, 0)")
        time.sleep(0.5)

        screenshot = _take_screenshot(session_id)

        # Restore viewport
        _wd(f"/session/{session_id}/window/rect", method="POST",
            body={"width": VIEWPORT_WIDTH, "height": VIEWPORT_HEIGHT})

        if not screenshot:
            return {"success": False, "error": "Failed to take screenshot."}

        return {
            "success": True,
            "screenshot": screenshot,
            "tiled": False,
            "dimensions": {"width": content_w, "height": content_h}
        }
    else:
        # Tiled mode: scroll and capture overlapping tiles
        overlap = 100  # pixels of overlap between tiles
        step = VIEWPORT_HEIGHT - overlap
        tiles = []
        pos = 0

        while pos < content_h:
            _execute_js(session_id, f"window.scrollTo(0, {pos})")
            time.sleep(0.5)
            tile = _take_screenshot(session_id)
            if tile:
                tiles.append(tile)
            # Stop if this tile already covers to near the bottom of content
            if pos + VIEWPORT_HEIGHT >= content_h - VIEWPORT_HEIGHT * 0.1:
                break
            pos += step
            # Safety: max 10 tiles
            if len(tiles) >= 10:
                break

        if not tiles:
            return {"success": False, "error": "Failed to capture tiled screenshots."}

        # Scroll back to top
        _execute_js(session_id, "window.scrollTo(0, 0)")

        return {
            "success": True,
            "screenshots": tiles,
            "tiled": True,
            "tile_count": len(tiles),
            "dimensions": {"width": content_w, "height": content_h}
        }


def action_extract_svg(args):
    """Extract SVG element from the current page and save to a file."""
    session_id = _load_session()
    if not session_id:
        return {"success": False, "error": "No active browser session. Use --action start first."}

    # Extract SVG outerHTML from DOM
    svg_js = """
    var svg = document.querySelector('svg');
    if (!svg) return null;
    // Ensure standalone SVG with xmlns
    if (!svg.getAttribute('xmlns')) {
        svg.setAttribute('xmlns', 'http://www.w3.org/2000/svg');
    }
    return svg.outerHTML;
    """
    result = _execute_js(session_id, svg_js)
    svg_content = result.get("value")

    if not svg_content:
        return {"success": False, "error": "No SVG element found on the page."}

    # Save SVG to file
    timestamp = int(time.time() * 1000)
    filename = f"diagram_{timestamp}.svg"
    filepath = os.path.join(SCREENSHOT_DIR, filename)

    with open(filepath, "w", encoding="utf-8") as f:
        # Add XML declaration for standalone SVG
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n')
        f.write(svg_content)

    return {
        "success": True,
        "svg_file": filename,
        "size": len(svg_content)
    }


def action_diagram_screenshot(args):
    """Take a screenshot of a rendered diagram, waiting for SVG to fully render.

    Unlike full_screenshot which uses scrollHeight (unreliable for async-rendered
    diagrams like DrawIO), this action polls for an SVG element, reads its exact
    bounding box, resizes the browser to fit, and takes a pixel-perfect capture.
    """
    session_id = _load_session()
    if not session_id:
        return {"success": False, "error": "No active browser session. Use --action start first."}

    # Poll for SVG element to appear and stabilize (DrawIO viewer renders async)
    max_wait = 10  # seconds
    poll_interval = 0.5
    elapsed = 0
    svg_dims = None

    while elapsed < max_wait:
        dims_js = """
        var svg = document.querySelector('svg');
        if (!svg) return null;
        var rect = svg.getBoundingClientRect();
        if (rect.width < 10 || rect.height < 10) return null;
        return {w: Math.ceil(rect.width), h: Math.ceil(rect.height)};
        """
        result = _execute_js(session_id, dims_js)
        dims = result.get("value")
        if dims and dims.get("w") and dims.get("h"):
            svg_dims = dims
            break
        time.sleep(poll_interval)
        elapsed += poll_interval

    if not svg_dims:
        return {"success": False, "error": "SVG element did not appear within timeout."}

    # Wait a bit more for any final rendering (CSS transitions, font loading)
    time.sleep(1)

    # Re-measure after stabilization
    result = _execute_js(session_id, """
    var svg = document.querySelector('svg');
    if (!svg) return null;
    var rect = svg.getBoundingClientRect();
    return {w: Math.ceil(rect.width), h: Math.ceil(rect.height)};
    """)
    final_dims = result.get("value")
    if final_dims and final_dims.get("w") and final_dims.get("h"):
        svg_dims = final_dims

    # Add padding around the diagram
    padding = 40
    target_w = min(svg_dims["w"] + padding * 2, 4000)
    target_h = min(svg_dims["h"] + padding * 2, 4000)

    # Resize browser window to fit the diagram exactly
    _wd(f"/session/{session_id}/window/rect", method="POST",
        body={"width": target_w, "height": target_h})
    time.sleep(1)

    # Scroll to top-left corner
    _execute_js(session_id, "window.scrollTo(0, 0)")
    time.sleep(0.5)

    # Take the screenshot
    screenshot = _take_screenshot(session_id)

    # Restore original viewport size
    _wd(f"/session/{session_id}/window/rect", method="POST",
        body={"width": VIEWPORT_WIDTH, "height": VIEWPORT_HEIGHT})

    if not screenshot:
        return {"success": False, "error": "Failed to take diagram screenshot."}

    return {
        "success": True,
        "screenshot": screenshot,
        "dimensions": {"width": svg_dims["w"], "height": svg_dims["h"]}
    }


def action_scroll(args):
    """Scroll the page in a direction. Supports up/down (relative) and top/bottom (absolute)."""
    session_id = _load_session()
    if not session_id:
        return {"success": False, "error": "No active browser session. Use --action start first."}

    direction = args.direction or "down"
    amount = args.amount or 500

    if direction == "bottom":
        js = "window.scrollTo(0, document.body.scrollHeight); return {scrollY: window.scrollY, scrollHeight: document.body.scrollHeight};"
    elif direction == "top":
        js = "window.scrollTo(0, 0); return {scrollY: window.scrollY, scrollHeight: document.body.scrollHeight};"
    else:
        if direction == "up":
            amount = -abs(amount)
        else:
            amount = abs(amount)
        js = f"window.scrollBy(0, {amount}); return {{scrollY: window.scrollY, scrollHeight: document.body.scrollHeight}};"

    r = _execute_js(session_id, js)

    time.sleep(0.5)
    screenshot = _take_screenshot(session_id)
    page_info = _get_page_info(session_id)

    scroll_info = r.get("value", {})

    return {
        "success": True,
        "scroll": scroll_info,
        "screenshot": screenshot,
        "page_info": page_info
    }


def action_press_key(args):
    """Send a key press using WebDriver Actions API.
    Automatically detects and switches to new tabs opened by the key press."""
    session_id = _load_session()
    if not session_id:
        return {"success": False, "error": "No active browser session. Use --action start first."}

    # Map key names to WebDriver key codes (Unicode PUA)
    key_map = {
        "Enter": "\uE007",
        "Escape": "\uE00C",
        "Tab": "\uE004",
        "ArrowUp": "\uE013",
        "ArrowDown": "\uE015",
        "ArrowLeft": "\uE012",
        "ArrowRight": "\uE014",
        "Backspace": "\uE003",
        "Space": "\uE00D",
    }

    key_name = args.key
    key_code = key_map.get(key_name)
    if not key_code:
        return {
            "success": False,
            "error": f"Unsupported key: {key_name}. Supported keys: {', '.join(key_map.keys())}"
        }

    # If a selector is provided, focus the element first
    if args.selector:
        js = """
        var el = document.querySelector(arguments[0]);
        if (!el) return {found: false};
        el.scrollIntoView({behavior: 'smooth', block: 'center'});
        el.focus();
        return {found: true, tag: el.tagName};
        """
        r = _execute_js(session_id, js, [args.selector])
        result = r.get("value", {})
        if not result or not result.get("found"):
            return {"success": False, "error": f"Element not found: {args.selector}"}
        time.sleep(0.3)

    # Record window handles before key press (Enter can open new tabs)
    handles_before = _get_window_handles(session_id)

    # Send key via WebDriver Actions API
    actions = {
        "actions": [
            {
                "type": "key",
                "id": "keyboard",
                "actions": [
                    {"type": "keyDown", "value": key_code},
                    {"type": "keyUp", "value": key_code}
                ]
            }
        ]
    }
    r = _wd(f"/session/{session_id}/actions", method="POST", body=actions)

    if "error" in r:
        return {"success": False, "error": f"Key press failed: {r['error']}"}

    # Release all actions
    _wd(f"/session/{session_id}/actions", method="DELETE")

    time.sleep(0.5)

    # Detect and switch to new tab if one was opened
    switched = _handle_new_tab(session_id, handles_before)
    if switched:
        time.sleep(1)

    screenshot = _take_screenshot(session_id)
    page_info = _get_page_info(session_id)

    response = {
        "success": True,
        "key": key_name,
        "screenshot": screenshot,
        "page_info": page_info
    }

    if switched:
        response["tab_switched"] = True
        response["message"] = "Key press opened a new tab; automatically switched to it."

    return response


def action_select(args):
    """Select an option from a <select> dropdown."""
    session_id = _load_session()
    if not session_id:
        return {"success": False, "error": "No active browser session. Use --action start first."}

    selector = args.selector
    value = args.value
    text = args.text

    if not value and not text:
        return {"success": False, "error": "Either --value or --text must be provided for select action."}

    # JavaScript to select an option by value or text
    js = """
    var el = document.querySelector(arguments[0]);
    if (!el) return {found: false};
    if (el.tagName.toLowerCase() !== 'select') return {found: true, error: 'Element is not a <select>'};

    var matchValue = arguments[1];
    var matchText = arguments[2];
    var options = Array.from(el.options);
    var matched = false;
    var available = [];

    for (var i = 0; i < options.length; i++) {
        available.push({value: options[i].value, text: options[i].text.trim()});
        if (matchValue && options[i].value === matchValue) {
            el.selectedIndex = i;
            matched = true;
            break;
        }
        if (matchText && options[i].text.trim().toLowerCase().includes(matchText.toLowerCase())) {
            el.selectedIndex = i;
            matched = true;
            break;
        }
    }

    if (!matched) {
        return {found: true, matched: false, available_options: available};
    }

    // Dispatch change and input events
    el.dispatchEvent(new Event('change', {bubbles: true}));
    el.dispatchEvent(new Event('input', {bubbles: true}));

    var selected = el.options[el.selectedIndex];
    return {found: true, matched: true, selected_value: selected.value, selected_text: selected.text.trim()};
    """
    r = _execute_js(session_id, js, [selector, value or "", text or ""])

    if "error" in r:
        return {"success": False, "error": f"Select failed: {r['error']}"}

    result = r.get("value", {})
    if not result or not result.get("found"):
        return {"success": False, "error": f"Element not found: {selector}"}

    if result.get("error"):
        return {"success": False, "error": result["error"]}

    if not result.get("matched"):
        return {
            "success": False,
            "error": "No matching option found.",
            "available_options": result.get("available_options", [])
        }

    time.sleep(0.5)
    screenshot = _take_screenshot(session_id)
    page_info = _get_page_info(session_id)

    return {
        "success": True,
        "selected": {
            "value": result.get("selected_value"),
            "text": result.get("selected_text")
        },
        "screenshot": screenshot,
        "page_info": page_info
    }


def action_back(args):
    """Navigate back in browser history."""
    session_id = _load_session()
    if not session_id:
        return {"success": False, "error": "No active browser session. Use --action start first."}

    r = _wd(f"/session/{session_id}/back", method="POST", body={})
    if "error" in r:
        return {"success": False, "error": f"Back navigation failed: {r['error']}"}

    time.sleep(1)
    screenshot = _take_screenshot(session_id)
    page_info = _get_page_info(session_id)

    return {
        "success": True,
        "screenshot": screenshot,
        "page_info": page_info
    }


def action_forward(args):
    """Navigate forward in browser history."""
    session_id = _load_session()
    if not session_id:
        return {"success": False, "error": "No active browser session. Use --action start first."}

    r = _wd(f"/session/{session_id}/forward", method="POST", body={})
    if "error" in r:
        return {"success": False, "error": f"Forward navigation failed: {r['error']}"}

    time.sleep(1)
    screenshot = _take_screenshot(session_id)
    page_info = _get_page_info(session_id)

    return {
        "success": True,
        "screenshot": screenshot,
        "page_info": page_info
    }


def action_stop(args):
    """Stop the browser session."""
    session_id = _load_session()
    if not session_id:
        return {"success": True, "message": "No active session to stop."}

    _wd(f"/session/{session_id}", method="DELETE")
    _clear_session()

    return {
        "success": True,
        "message": "Browser session ended."
    }


def main():
    parser = argparse.ArgumentParser(description="Interactive Web Navigator")
    parser.add_argument("--action", required=True,
                        choices=["start", "navigate", "click", "type",
                                 "screenshot", "full_screenshot",
                                 "diagram_screenshot", "extract_svg",
                                 "get_page_info", "scroll",
                                 "press_key", "select", "back", "forward",
                                 "stop"],
                        help="Action to perform")
    parser.add_argument("--url", help="URL for start/navigate actions")
    parser.add_argument("--selector", help="CSS selector for click/type/press_key/select actions")
    parser.add_argument("--text", help="Text for type/select actions")
    parser.add_argument("--direction", choices=["up", "down", "top", "bottom"], default="down",
                        help="Scroll direction")
    parser.add_argument("--amount", type=int, default=500,
                        help="Scroll amount in pixels")
    parser.add_argument("--key", help="Key name for press_key action (e.g., Enter, Escape, Tab)")
    parser.add_argument("--value", help="Value for select action")

    args = parser.parse_args()

    actions = {
        "start": action_start,
        "navigate": action_navigate,
        "click": action_click,
        "type": action_type,
        "screenshot": action_screenshot,
        "full_screenshot": action_full_screenshot,
        "diagram_screenshot": action_diagram_screenshot,
        "extract_svg": action_extract_svg,
        "get_page_info": action_get_page_info,
        "scroll": action_scroll,
        "press_key": action_press_key,
        "select": action_select,
        "back": action_back,
        "forward": action_forward,
        "stop": action_stop,
    }

    result = actions[args.action](args)
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
