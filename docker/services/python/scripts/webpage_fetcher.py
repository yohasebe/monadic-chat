#!/usr/bin/env python

import sys
import time
import argparse
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
import os
from datetime import datetime
from urllib.parse import urlparse
from PIL import Image

def is_valid_url(url):
    try:
        result = urlparse(url)
        return bool(result.netloc)  # Check only if netloc is present
    except ValueError:
        return False

def ensure_scheme(url):
    if not urlparse(url).scheme:
        url = "https://" + url
    return url

def get_relative_path(basepath, output_path):
    if os.path.commonprefix([basepath, output_path]) == basepath:
        return output_path[len(basepath):].lstrip('/')
    else:
        return output_path

# Initialize the parser
parser = argparse.ArgumentParser(description='Capture webpage as PNG or convert to Markdown within a specified element.')

# Add arguments that are always available
parser.add_argument('--url', type=str, required=True, help='URL to access')
parser.add_argument('--mode', type=str, choices=['png', 'md'], default='md', help='Output mode: png for screenshot, md for markdown')
parser.add_argument('--output', type=str, choices=['file', 'stdout'], default='file', help='Output destination: file or stdout')
parser.add_argument('--filepath', type=str, default='./', help='Path to the directory for saving the output data (when output=file)')
parser.add_argument('--fullpage', type=str, choices=['true', 'false'], default='false', help='Capture/convert the full page: true or false')
parser.add_argument('--timeout-sec', type=int, default=30, help='Maximum time in seconds before the process is canceled')

# First parse known args to check the mode
args, unknown = parser.parse_known_args()

# Since --mode defaults to 'md', we add the --element argument if mode is 'md'
if args.mode == 'md':
    parser.add_argument('--element', type=str, help='CSS selector of the element to capture/convert when mode is set to md')

# Parse args again to include the conditional argument
args = parser.parse_args()

# Ensure URL has a scheme
args.url = ensure_scheme(args.url)

# Validate URL
if not is_valid_url(args.url):
    print(f"Error: The URL '{args.url}' is invalid or incomplete. Please provide a valid URL.", file=sys.stderr)
    sys.exit(1)

# Only create output directory if output mode is 'file'
output_dir = None
output_path = None
if args.output == 'file':
    output_dir = os.path.abspath(args.filepath)
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)
    
    # Generate filename based on current timestamp and selected mode
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    filename = f"{timestamp}.{args.mode}"
    output_path = os.path.join(output_dir, filename)

# Initialize driver
driver = None

try:
    # Chrome Options settings
    options = Options()
    options.add_argument('--headless')
    options.add_argument('--disable-gpu')
    options.add_argument('--proxy-server="direct://"')
    options.add_argument('--proxy-bypass-list=*')
    options.add_argument('--hide-scrollbars')

    driver = webdriver.Remote(
        command_executor='http://selenium_service:4444/wd/hub',
        options=options
    )

    driver.get(args.url)
    time.sleep(3)  # Give the page some time to load

    # Find the element by CSS selector if specified and mode is 'md'
    element = None
    if args.mode == 'md':
        if hasattr(args, 'element') and args.element:
            try:
                element = driver.find_element(By.CSS_SELECTOR, args.element)
            except Exception as e:
                print(f"Error: Could not find element with CSS selector '{args.element}'. {e}", file=sys.stderr)
                sys.exit(1)
        else:
            # If no specific element is provided, default to capturing the entire body
            element = driver.find_element(By.TAG_NAME, 'body')

    if args.mode == 'png':
        # PNG mode cannot output to stdout due to binary data
        if args.output == 'stdout':
            print("Error: PNG mode cannot output to stdout", file=sys.stderr)
            sys.exit(1)
            
        # Take screenshot of either the specified element or full page
        if args.fullpage == 'false' and hasattr(args, 'element') and args.element:
            element.screenshot(output_path)
        else:
            driver.save_screenshot(output_path)
            
        # Check if the PNG file is essentially blank
        with Image.open(output_path) as img:
            extrema = img.convert("L").getextrema()
        if extrema == (0, 0) or extrema == (255, 255):
            os.remove(output_path)
            print(f"Removed {output_path} as it was a blank image.", file=sys.stderr)
            sys.exit(1)
        else:
            print(f"Content successfully saved to: {output_path}", file=sys.stderr)
            
    elif args.mode == 'md':
        if element is not None:
            extracted = element.text
            if args.output == 'file':
                # Save content to file
                with open(output_path, 'w') as f:
                    f.write(extracted)
                # Verify the content is not empty
                with open(output_path, 'r') as f:
                    content = f.read().strip()
                if not content:
                    os.remove(output_path)
                    print(f"Removed {output_path} as it contained no meaningful data.", file=sys.stderr)
                    sys.exit(1)
                else:
                    print(f"Content successfully saved to: {output_path}", file=sys.stderr)
            else:  # stdout mode
                # Check for meaningful content before printing
                if not extracted.strip():
                    print("Error: No meaningful content found", file=sys.stderr)
                    sys.exit(1)
                print(extracted)  # Print to stdout

except Exception as e:
    print(f"An error occurred: {e}", file=sys.stderr)
finally:
    if driver:
        driver.quit()
