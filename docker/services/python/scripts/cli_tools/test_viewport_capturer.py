#!/usr/bin/env python3
"""
Unit tests for viewport_capturer.py
"""

import unittest
from unittest.mock import Mock, MagicMock, patch, call
import os
import sys
import json
from datetime import datetime

# Mock selenium before import
sys.modules['selenium'] = MagicMock()
sys.modules['selenium.webdriver'] = MagicMock()
sys.modules['selenium.webdriver.chrome.options'] = MagicMock()
sys.modules['selenium.webdriver.common.by'] = MagicMock()
sys.modules['selenium.webdriver.support.ui'] = MagicMock()
sys.modules['selenium.webdriver.support'] = MagicMock()
sys.modules['selenium.common.exceptions'] = MagicMock()

# Add the parent directory to the path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import viewport_capturer

class TestViewportCapturer(unittest.TestCase):
    def setUp(self):
        """Set up test fixtures"""
        self.test_url = "https://example.com"
        self.test_output_dir = "/tmp/test_screenshots"
        
    @patch('viewport_capturer.webdriver.Remote')
    def test_create_driver(self, mock_remote):
        """Test WebDriver creation with correct options"""
        mock_driver = MagicMock()
        mock_remote.return_value = mock_driver
        
        driver = viewport_capturer.create_driver()
        
        # Verify Remote was called with correct parameters
        mock_remote.assert_called_once()
        call_args = mock_remote.call_args
        self.assertEqual(call_args[1]['command_executor'], 'http://selenium_service:4444/wd/hub')
        
        # Verify options were set correctly
        options = call_args[1]['options']
        self.assertIsNotNone(options)
        
    def test_sanitize_filename(self):
        """Test filename sanitization"""
        test_cases = [
            ("https://example.com/page", "https___example_com_page"),
            ("test@file#name.html", "test_file_name_html"),
            ("file with spaces", "file_with_spaces"),
            ("file/with/slashes", "file_with_slashes"),
        ]
        
        for input_name, expected in test_cases:
            result = viewport_capturer.sanitize_filename(input_name)
            self.assertEqual(result, expected)
    
    def test_ensure_output_directory_exists(self):
        """Test output directory creation"""
        with patch('os.makedirs') as mock_makedirs:
            with patch('os.path.exists', return_value=False):
                viewport_capturer.ensure_output_directory("/test/dir")
                mock_makedirs.assert_called_once_with("/test/dir", exist_ok=True)
    
    def test_ensure_output_directory_already_exists(self):
        """Test when output directory already exists"""
        with patch('os.makedirs') as mock_makedirs:
            with patch('os.path.exists', return_value=True):
                viewport_capturer.ensure_output_directory("/test/dir")
                mock_makedirs.assert_not_called()
    
    @patch('viewport_capturer.create_driver')
    @patch('viewport_capturer.ensure_output_directory')
    def test_capture_viewport_screenshots_success(self, mock_ensure_dir, mock_create_driver):
        """Test successful viewport screenshot capture"""
        # Mock driver
        mock_driver = MagicMock()
        mock_create_driver.return_value = mock_driver
        
        # Mock driver methods
        mock_driver.get.return_value = None
        mock_driver.execute_script.side_effect = [
            1920,  # viewport width
            1080,  # viewport height
            3000,  # page height
            0,     # initial scroll position
            1080,  # scroll to second viewport
            2000,  # scroll to third viewport
            3000   # final scroll position
        ]
        mock_driver.save_screenshot.return_value = True
        
        # Test capture
        result = viewport_capturer.capture_viewport_screenshots(
            self.test_url,
            self.test_output_dir,
            wait_time=0.1,
            scroll_pause=0.1
        )
        
        # Verify results
        self.assertTrue(result['success'])
        self.assertEqual(result['url'], self.test_url)
        self.assertEqual(len(result['screenshots']), 3)
        self.assertEqual(result['page_info']['viewport_width'], 1920)
        self.assertEqual(result['page_info']['viewport_height'], 1080)
        self.assertEqual(result['page_info']['total_height'], 3000)
        
        # Verify driver interactions
        mock_driver.get.assert_called_once_with(self.test_url)
        self.assertEqual(mock_driver.save_screenshot.call_count, 3)
        mock_driver.quit.assert_called_once()
    
    @patch('viewport_capturer.create_driver')
    def test_capture_viewport_screenshots_driver_error(self, mock_create_driver):
        """Test handling of WebDriver errors"""
        mock_create_driver.side_effect = Exception("WebDriver connection failed")
        
        result = viewport_capturer.capture_viewport_screenshots(
            self.test_url,
            self.test_output_dir
        )
        
        self.assertFalse(result['success'])
        self.assertIn("WebDriver connection failed", result['error'])
    
    @patch('viewport_capturer.create_driver')
    def test_capture_viewport_screenshots_navigation_error(self, mock_create_driver):
        """Test handling of navigation errors"""
        mock_driver = MagicMock()
        mock_create_driver.return_value = mock_driver
        mock_driver.get.side_effect = Exception("Navigation failed")
        
        result = viewport_capturer.capture_viewport_screenshots(
            self.test_url,
            self.test_output_dir
        )
        
        self.assertFalse(result['success'])
        self.assertIn("Navigation failed", result['error'])
        mock_driver.quit.assert_called_once()
    
    def test_create_screenshot_gallery(self):
        """Test HTML gallery generation"""
        screenshots = [
            "screenshot_1.png",
            "screenshot_2.png",
            "screenshot_3.png"
        ]
        base_name = "example_com"
        
        html = viewport_capturer.create_screenshot_gallery(screenshots, base_name)
        
        # Verify HTML structure
        self.assertIn("Screenshot Gallery", html)
        self.assertIn("screenshot_1.png", html)
        self.assertIn("screenshot_2.png", html)
        self.assertIn("screenshot_3.png", html)
        self.assertIn("Viewport 1", html)
        self.assertIn("Viewport 2", html)
        self.assertIn("Viewport 3", html)
        self.assertIn('<div class="generated_image">', html)
    
    def test_main_function_arguments(self):
        """Test command line argument parsing"""
        test_args = [
            'viewport_capturer.py',
            'https://example.com',
            '/tmp/output'
        ]
        
        with patch('sys.argv', test_args):
            with patch('viewport_capturer.capture_viewport_screenshots') as mock_capture:
                mock_capture.return_value = {
                    'success': True,
                    'screenshots': ['test.png'],
                    'page_info': {},
                    'gallery_html': '<html></html>'
                }
                
                with patch('builtins.print'):
                    viewport_capturer.main()
                
                mock_capture.assert_called_once_with(
                    'https://example.com',
                    '/tmp/output',
                    wait_time=3,
                    scroll_pause=1
                )


if __name__ == '__main__':
    unittest.main()