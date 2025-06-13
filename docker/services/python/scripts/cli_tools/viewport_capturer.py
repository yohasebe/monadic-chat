#!/usr/bin/env python3
"""
Viewport-based Web Page Screenshot Capturer
Captures web pages as a series of viewport-sized screenshots with automatic scrolling
"""

import argparse
import os
import sys
import time
from pathlib import Path
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
# from selenium.webdriver.chrome.service import Service  # Not needed for Remote WebDriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.common.exceptions import TimeoutException, WebDriverException
from datetime import datetime
import re
from urllib.parse import urlparse
import logging

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(message)s')
logger = logging.getLogger(__name__)

def create_driver():
    """Create and configure Chrome WebDriver"""
    chrome_options = Options()
    chrome_options.add_argument("--headless")
    chrome_options.add_argument("--no-sandbox")
    chrome_options.add_argument("--disable-dev-shm-usage")
    chrome_options.add_argument("--disable-gpu")
    chrome_options.add_argument("--disable-web-security")
    chrome_options.add_argument("--disable-features=VizDisplayCompositor")
    chrome_options.add_argument("--disable-extensions")
    chrome_options.add_argument("--disable-plugins")
    chrome_options.add_argument("--disable-images")
    chrome_options.add_argument("--disable-javascript")
    chrome_options.add_argument("--enable-javascript")  # Re-enable JS for dynamic content
    chrome_options.add_argument("--start-maximized")
    
    driver = webdriver.Remote(
        command_executor='http://selenium_service:4444/wd/hub',
        options=chrome_options
    )
    
    return driver

def sanitize_filename(filename):
    """Sanitize filename for safe file system usage"""
    # Remove or replace invalid characters
    filename = re.sub(r'[<>:"/\\|?*]', '_', filename)
    # Limit length
    return filename[:100]

def take_viewport_screenshots(driver, url, output_dir, viewport_width=1920, viewport_height=1080, overlap=0):
    """
    Take multiple viewport-sized screenshots of a webpage
    
    Args:
        driver: Selenium WebDriver instance
        url: URL to capture
        output_dir: Directory to save screenshots
        viewport_width: Width of viewport in pixels
        viewport_height: Height of viewport in pixels
        overlap: Number of pixels to overlap between screenshots
    
    Returns:
        List of saved screenshot filenames
    """
    screenshots = []
    
    try:
        # Navigate to URL
        logger.info(f"Loading URL: {url}")
        driver.get(url)
        
        # Wait for page load
        WebDriverWait(driver, 30).until(
            lambda d: d.execute_script("return document.readyState") == "complete"
        )
        time.sleep(2)  # Additional wait for dynamic content
        
        # Set viewport size
        driver.set_window_size(viewport_width, viewport_height)
        logger.info(f"Viewport size set to: {viewport_width}x{viewport_height}")
        
        # Get page dimensions
        total_height = driver.execute_script("return document.body.scrollHeight")
        page_width = driver.execute_script("return document.body.scrollWidth")
        
        logger.info(f"Page dimensions: {page_width}x{total_height}")
        
        # Calculate scroll positions
        scroll_step = viewport_height - overlap
        current_position = 0
        screenshot_count = 0
        
        # Create base filename from URL
        parsed_url = urlparse(url)
        domain = parsed_url.netloc.replace('www.', '').replace('.', '_')
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        base_filename = f"{domain}_{timestamp}"
        
        while current_position < total_height:
            # Scroll to position
            driver.execute_script(f"window.scrollTo(0, {current_position})")
            time.sleep(0.5)  # Wait for rendering
            
            # Take screenshot
            screenshot_count += 1
            filename = f"{base_filename}_viewport_{screenshot_count:03d}.png"
            filepath = os.path.join(output_dir, filename)
            
            driver.save_screenshot(filepath)
            
            # Verify screenshot was saved and is not empty
            if os.path.exists(filepath) and os.path.getsize(filepath) > 0:
                logger.info(f"Saved screenshot {screenshot_count}: {filename}")
                screenshots.append(filename)
            else:
                logger.error(f"Failed to save screenshot {screenshot_count}")
            
            # Move to next position
            current_position += scroll_step
            
            # Check if we've reached the bottom
            if current_position + viewport_height >= total_height:
                # Take one final screenshot if there's remaining content
                if current_position < total_height - 10:  # 10px threshold
                    driver.execute_script(f"window.scrollTo(0, {total_height - viewport_height})")
                    time.sleep(0.5)
                    
                    screenshot_count += 1
                    filename = f"{base_filename}_viewport_{screenshot_count:03d}.png"
                    filepath = os.path.join(output_dir, filename)
                    
                    driver.save_screenshot(filepath)
                    
                    if os.path.exists(filepath) and os.path.getsize(filepath) > 0:
                        logger.info(f"Saved final screenshot {screenshot_count}: {filename}")
                        screenshots.append(filename)
                
                break
        
        logger.info(f"Capture complete: {len(screenshots)} screenshots saved")
        
    except TimeoutException:
        logger.error("Page load timeout")
    except WebDriverException as e:
        logger.error(f"WebDriver error: {str(e)}")
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
    
    return screenshots

def main():
    parser = argparse.ArgumentParser(description='Capture web pages as viewport-sized screenshots')
    parser.add_argument('url', help='URL to capture')
    parser.add_argument('-o', '--output', default='/monadic/data', help='Output directory (default: /monadic/data)')
    parser.add_argument('-w', '--width', type=int, default=1920, help='Viewport width (default: 1920)')
    parser.add_argument('--height', type=int, default=1080, help='Viewport height (default: 1080)')
    parser.add_argument('--overlap', type=int, default=100, help='Overlap between screenshots in pixels (default: 100)')
    parser.add_argument('--preset', choices=['desktop', 'tablet', 'mobile', 'print'], 
                       help='Use preset viewport sizes')
    
    args = parser.parse_args()
    
    # Apply presets if specified
    if args.preset:
        presets = {
            'desktop': (1920, 1080),
            'tablet': (1024, 768),
            'mobile': (375, 812),  # iPhone X dimensions
            'print': (794, 1123)   # A4 at 96 DPI
        }
        args.width, args.height = presets[args.preset]
        logger.info(f"Using {args.preset} preset: {args.width}x{args.height}")
    
    # Ensure output directory exists
    os.makedirs(args.output, exist_ok=True)
    
    # Create driver and capture screenshots
    driver = None
    try:
        driver = create_driver()
        screenshots = take_viewport_screenshots(
            driver, 
            args.url, 
            args.output,
            viewport_width=args.width,
            viewport_height=args.height,
            overlap=args.overlap
        )
        
        if screenshots:
            print(f"SUCCESS: {len(screenshots)} screenshots saved")
            for screenshot in screenshots:
                print(f"  - {screenshot}")
        else:
            print("ERROR: No screenshots were captured")
            sys.exit(1)
            
    finally:
        if driver:
            driver.quit()

if __name__ == "__main__":
    main()