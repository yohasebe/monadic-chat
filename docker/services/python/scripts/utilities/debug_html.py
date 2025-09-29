#!/usr/bin/env python3
"""
HTML Debug Tool for AutoForge
Analyzes HTML files for errors and functionality using Selenium
"""

import argparse
import json
import sys
import time
import urllib.parse
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.common.exceptions import WebDriverException, TimeoutException
from pathlib import Path

def create_driver():
    """Create and configure Chrome WebDriver using remote Selenium service"""
    chrome_options = Options()
    chrome_options.add_argument("--headless")
    chrome_options.add_argument("--no-sandbox")
    chrome_options.add_argument("--disable-dev-shm-usage")
    chrome_options.add_argument("--disable-gpu")
    chrome_options.add_argument("--disable-web-security")
    chrome_options.add_argument("--enable-javascript")

    # Connect to Selenium service (same as viewport_capturer.py)
    driver = webdriver.Remote(
        command_executor='http://selenium_service:4444/wd/hub',
        options=chrome_options
    )

    return driver

def debug_html(html_path):
    """Debug an HTML file and return analysis results"""
    debug_start = time.time()
    results = {
        'success': True,
        'errors': [],
        'warnings': [],
        'console_logs': [],
        'javascript_errors': [],
        'performance': {},
        'functionality_tests': [],
        'selenium_timing': {}
    }

    driver = None

    try:
        # Normalize and validate path
        html_path = str(Path(html_path).resolve())

        # Check if file exists
        if not Path(html_path).exists():
            results['success'] = False
            results['errors'].append(f"HTML file not found: {html_path}")
            return results

        # Create driver
        selenium_connect_start = time.time()
        driver = create_driver()
        selenium_connect_time = time.time() - selenium_connect_start
        results['selenium_timing']['connect_time'] = round(selenium_connect_time, 2)

        # Load the HTML file with proper URL encoding for special characters
        page_load_start = time.time()
        # Properly encode the file path for URL
        file_url = "file://" + urllib.parse.quote(html_path, safe='/')
        driver.get(file_url)

        # Wait for page to load
        time.sleep(2)
        page_load_time = time.time() - page_load_start
        results['selenium_timing']['page_load_time'] = round(page_load_time, 2)

        # Check for JavaScript errors (try-catch for compatibility)
        try:
            logs = driver.get_log('browser')
            for log in logs:
                if log['level'] == 'SEVERE':
                    results['javascript_errors'].append({
                        'message': log['message'],
                        'timestamp': log['timestamp']
                    })
                elif log['level'] == 'WARNING':
                    results['warnings'].append({
                        'message': log['message'],
                        'timestamp': log['timestamp']
                    })
                else:
                    results['console_logs'].append({
                        'level': log['level'],
                        'message': log['message'],
                        'timestamp': log['timestamp']
                    })
        except Exception as e:
            # Log retrieval might not be supported in all WebDriver configurations
            results['warnings'].append({
                'message': f'Could not retrieve browser logs: {str(e)}',
                'timestamp': time.time()
            })

        # Check page title
        if driver.title:
            results['page_title'] = driver.title

        # Check for common UI elements
        results['functionality_tests'].append({
            'test': 'Page loads without critical errors',
            'passed': len(results['javascript_errors']) == 0
        })

        # Check for forms
        forms = driver.find_elements(By.TAG_NAME, 'form')
        if forms:
            results['functionality_tests'].append({
                'test': f'Found {len(forms)} form(s)',
                'passed': True,
                'count': len(forms)
            })

        # Check for buttons
        buttons = driver.find_elements(By.TAG_NAME, 'button')
        inputs = driver.find_elements(By.CSS_SELECTOR, 'input[type="button"], input[type="submit"]')
        total_buttons = len(buttons) + len(inputs)
        if total_buttons > 0:
            results['functionality_tests'].append({
                'test': f'Found {total_buttons} button(s)',
                'passed': True,
                'count': total_buttons
            })

        # Check for interactive elements
        interactive = driver.find_elements(By.CSS_SELECTOR, 'input, textarea, select, button, a[href]')
        results['functionality_tests'].append({
            'test': f'Found {len(interactive)} interactive element(s)',
            'passed': len(interactive) > 0,
            'count': len(interactive)
        })

        # Execute simple JavaScript to test if JS is working
        try:
            js_test = driver.execute_script("return typeof document !== 'undefined' && document.body !== null;")
            results['functionality_tests'].append({
                'test': 'JavaScript execution',
                'passed': js_test == True
            })
        except Exception as e:
            results['functionality_tests'].append({
                'test': 'JavaScript execution',
                'passed': False,
                'error': str(e)
            })

        # Get performance metrics
        try:
            performance = driver.execute_script("""
                var performance = window.performance || {};
                var timing = performance.timing || {};
                return {
                    'loadTime': timing.loadEventEnd - timing.navigationStart,
                    'domReadyTime': timing.domContentLoadedEventEnd - timing.navigationStart,
                    'renderTime': timing.domComplete - timing.domLoading
                };
            """)
            results['performance'] = performance
        except Exception:
            pass

    except WebDriverException as e:
        results['success'] = False
        error_msg = f"WebDriver error: {str(e)}"
        # Add helpful context for common issues
        if "file://" in str(e):
            error_msg += " (Note: File path may contain special characters)"
        results['errors'].append(error_msg)
    except Exception as e:
        results['success'] = False
        error_msg = f"Unexpected error: {str(e)}"
        # Add debugging info
        error_msg += f" | HTML path: {html_path if 'html_path' in locals() else 'unknown'}"
        results['errors'].append(error_msg)
    finally:
        if driver:
            driver.quit()

    # Add timing information
    debug_end = time.time()
    results['selenium_timing']['total_duration'] = round(debug_end - debug_start, 2)

    return results

def main():
    parser = argparse.ArgumentParser(description='Debug HTML file using Selenium')
    parser.add_argument('html_path', help='Path to the HTML file to debug')
    parser.add_argument('--json', action='store_true', help='Output results as JSON')

    args = parser.parse_args()

    # Validate input
    try:
        # Strip any quotes that might have been included
        html_path = args.html_path.strip('"').strip("'")
    except Exception as e:
        results = {
            'success': False,
            'errors': [f"Invalid path argument: {str(e)}"]
        }
        if args.json:
            print(json.dumps(results, indent=2))
        else:
            print(f"ERROR: {results['errors'][0]}")
        sys.exit(1)

    # Run debug
    results = debug_html(html_path)

    # Output results
    if args.json:
        print(json.dumps(results, indent=2))
    else:
        # Human-readable output
        if results['success']:
            print("SUCCESS: HTML debug completed")
        else:
            print("ERROR: Debug failed")

        if results['javascript_errors']:
            print("\nJavaScript Errors:")
            for error in results['javascript_errors']:
                print(f"  - {error['message']}")

        if results['warnings']:
            print("\nWarnings:")
            for warning in results['warnings']:
                print(f"  - {warning['message']}")

        if results['functionality_tests']:
            print("\nFunctionality Tests:")
            for test in results['functionality_tests']:
                status = "✓" if test['passed'] else "✗"
                print(f"  {status} {test['test']}")

        if results['selenium_timing']:
            print(f"\nTiming:")
            print(f"  Total: {results['selenium_timing'].get('total_duration', 'N/A')}s")
            print(f"  Connect: {results['selenium_timing'].get('connect_time', 'N/A')}s")
            print(f"  Load: {results['selenium_timing'].get('page_load_time', 'N/A')}s")

if __name__ == "__main__":
    main()