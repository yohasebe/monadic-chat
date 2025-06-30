#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Unit tests for jupyter_controller.py

This test suite verifies the functionality of the Jupyter notebook controller
used by Monadic Chat to manage Jupyter notebooks programmatically.

Run tests:
    python3 test_jupyter_controller.py
    or
    python3 -m pytest test_jupyter_controller.py -v
"""

import unittest
import tempfile
import shutil
import os
import json
import sys
from unittest.mock import patch, MagicMock

# Add the parent directory to the path to import jupyter_controller
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import jupyter_controller

class TestJupyterController(unittest.TestCase):
    def setUp(self):
        """Set up test environment before each test"""
        self.test_dir = tempfile.mkdtemp()
        self.original_data_dir = "/monadic/data"
        # Patch the data directory to use our test directory
        self.patcher = patch.object(jupyter_controller, 'get_notebook_path', 
                                    lambda x: os.path.join(self.test_dir, x if x.endswith('.ipynb') else f"{x}.ipynb"))
        self.patcher.start()
        
    def tearDown(self):
        """Clean up test environment after each test"""
        self.patcher.stop()
        shutil.rmtree(self.test_dir)
        
    def test_get_notebook_path(self):
        """Test notebook path generation"""
        self.patcher.stop()  # Temporarily stop patching for this test
        self.assertEqual(jupyter_controller.get_notebook_path("test"), "/monadic/data/test.ipynb")
        self.assertEqual(jupyter_controller.get_notebook_path("test.ipynb"), "/monadic/data/test.ipynb")
        self.patcher.start()
        
    def test_get_json_path(self):
        """Test JSON path generation"""
        self.assertEqual(jupyter_controller.get_json_path("test"), "/monadic/data/test.json")
        self.assertEqual(jupyter_controller.get_json_path("test.json"), "/monadic/data/test.json")
        
    def test_create_notebook(self):
        """Test notebook creation"""
        notebook_path = os.path.join(self.test_dir, "test.ipynb")
        jupyter_controller.create_notebook(notebook_path)
        
        self.assertTrue(os.path.exists(notebook_path))
        
        # Verify it's a valid notebook
        nb = jupyter_controller.read_notebook(notebook_path)
        self.assertIn('cells', nb)
        self.assertEqual(len(nb['cells']), 0)
        
    def test_notebook_exists(self):
        """Test notebook existence check"""
        notebook_path = os.path.join(self.test_dir, "test.ipynb")
        
        self.assertFalse(jupyter_controller.notebook_exists(notebook_path))
        
        jupyter_controller.create_notebook(notebook_path)
        self.assertTrue(jupyter_controller.notebook_exists(notebook_path))
        
    def test_add_cells_to_notebook(self):
        """Test adding cells to notebook"""
        notebook_path = os.path.join(self.test_dir, "test.ipynb")
        jupyter_controller.create_notebook(notebook_path)
        
        # Test adding markdown cell
        cells = [{
            'type': 'markdown',
            'content': '# Test Header'
        }]
        jupyter_controller.add_cells_to_notebook(notebook_path, cells)
        
        nb = jupyter_controller.read_notebook(notebook_path)
        self.assertEqual(len(nb['cells']), 1)
        self.assertEqual(nb['cells'][0]['cell_type'], 'markdown')
        self.assertEqual(nb['cells'][0]['source'], '# Test Header')
        
        # Test adding code cell
        cells = [{
            'type': 'code',
            'content': 'print("Hello World")'
        }]
        jupyter_controller.add_cells_to_notebook(notebook_path, cells)
        
        nb = jupyter_controller.read_notebook(notebook_path)
        self.assertEqual(len(nb['cells']), 2)
        self.assertEqual(nb['cells'][1]['cell_type'], 'code')
        self.assertEqual(nb['cells'][1]['source'], 'print("Hello World")')
        
    def test_add_cells_with_source_field(self):
        """Test adding cells using 'source' field instead of 'content'"""
        notebook_path = os.path.join(self.test_dir, "test.ipynb")
        jupyter_controller.create_notebook(notebook_path)
        
        # Test with source as string
        cells = [{
            'cell_type': 'markdown',
            'source': '# Test with source field'
        }]
        jupyter_controller.add_cells_to_notebook(notebook_path, cells)
        
        nb = jupyter_controller.read_notebook(notebook_path)
        self.assertEqual(len(nb['cells']), 1)
        self.assertEqual(nb['cells'][0]['source'], '# Test with source field')
        
        # Test with source as list
        cells = [{
            'cell_type': 'code',
            'source': ['import numpy as np\n', 'import pandas as pd\n', 'print("Test")']
        }]
        jupyter_controller.add_cells_to_notebook(notebook_path, cells)
        
        nb = jupyter_controller.read_notebook(notebook_path)
        self.assertEqual(len(nb['cells']), 2)
        self.assertEqual(nb['cells'][1]['source'], 'import numpy as np\nimport pandas as pd\nprint("Test")')
        
    def test_delete_cell(self):
        """Test deleting a cell from notebook"""
        notebook_path = os.path.join(self.test_dir, "test.ipynb")
        jupyter_controller.create_notebook(notebook_path)
        
        # Add some cells
        cells = [
            {'type': 'markdown', 'content': '# Cell 1'},
            {'type': 'code', 'content': 'print("Cell 2")'},
            {'type': 'markdown', 'content': '# Cell 3'}
        ]
        jupyter_controller.add_cells_to_notebook(notebook_path, cells)
        
        # Delete middle cell
        jupyter_controller.delete_cell(notebook_path, 1)
        
        nb = jupyter_controller.read_notebook(notebook_path)
        self.assertEqual(len(nb['cells']), 2)
        self.assertEqual(nb['cells'][0]['source'], '# Cell 1')
        self.assertEqual(nb['cells'][1]['source'], '# Cell 3')
        
        # Test deleting out of range cell
        jupyter_controller.delete_cell(notebook_path, 10)  # Should print error but not crash
        
    def test_update_cell(self):
        """Test updating a cell in notebook"""
        notebook_path = os.path.join(self.test_dir, "test.ipynb")
        jupyter_controller.create_notebook(notebook_path)
        
        # Add initial cell
        cells = [{'type': 'markdown', 'content': '# Original'}]
        jupyter_controller.add_cells_to_notebook(notebook_path, cells)
        
        # Update the cell
        jupyter_controller.update_cell(notebook_path, 0, '# Updated', 'markdown')
        
        nb = jupyter_controller.read_notebook(notebook_path)
        self.assertEqual(nb['cells'][0]['source'], '# Updated')
        
        # Update to code cell
        jupyter_controller.update_cell(notebook_path, 0, 'print("Now code")', 'code')
        
        nb = jupyter_controller.read_notebook(notebook_path)
        self.assertEqual(nb['cells'][0]['cell_type'], 'code')
        self.assertEqual(nb['cells'][0]['source'], 'print("Now code")')
        
    def test_search_cells(self):
        """Test searching for keywords in cells"""
        notebook_path = os.path.join(self.test_dir, "test.ipynb")
        jupyter_controller.create_notebook(notebook_path)
        
        # Add cells with different content
        cells = [
            {'type': 'markdown', 'content': '# Introduction to Python'},
            {'type': 'code', 'content': 'import pandas as pd'},
            {'type': 'markdown', 'content': 'Python is great'},
            {'type': 'code', 'content': 'data = pd.DataFrame()'}
        ]
        jupyter_controller.add_cells_to_notebook(notebook_path, cells)
        
        # Search for "Python"
        results = jupyter_controller.search_cells(notebook_path, "Python")
        self.assertEqual(len(results), 2)
        self.assertEqual(results[0][0], 0)  # First cell index
        self.assertEqual(results[1][0], 2)  # Third cell index
        
        # Search for "pandas"
        results = jupyter_controller.search_cells(notebook_path, "pandas")
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0][0], 1)  # Second cell index
        
    def test_read_write_retry_mechanism(self):
        """Test retry mechanism for read/write operations"""
        notebook_path = os.path.join(self.test_dir, "test.ipynb")
        jupyter_controller.create_notebook(notebook_path)
        
        # Mock file operations to fail initially
        original_open = open
        call_count = 0
        
        def mock_open(*args, **kwargs):
            nonlocal call_count
            call_count += 1
            if call_count <= 2:  # Fail first 2 attempts
                raise IOError("Simulated file lock")
            return original_open(*args, **kwargs)
        
        with patch('builtins.open', mock_open):
            # Should succeed after retries
            nb = jupyter_controller.read_notebook(notebook_path, max_retries=5, retry_delay=0.1)
            self.assertIsNotNone(nb)
            
    def test_invalid_cell_type(self):
        """Test handling of invalid cell types"""
        notebook_path = os.path.join(self.test_dir, "test.ipynb")
        jupyter_controller.create_notebook(notebook_path)
        
        # Try to add cell with invalid type
        cells = [{'type': 'invalid_type', 'content': 'Test'}]
        
        with self.assertRaises(ValueError) as context:
            jupyter_controller.add_cells_to_notebook(notebook_path, cells)
        self.assertIn("Invalid cell type", str(context.exception))
        
    def test_main_create_command(self):
        """Test main function with create command"""
        with patch('sys.argv', ['jupyter_controller.py', 'create', 'test_notebook']):
            with patch('builtins.print') as mock_print:
                jupyter_controller.main()
                
                # Check that notebook was created with timestamp
                calls = [str(call) for call in mock_print.call_args_list]
                self.assertTrue(any('Notebook created' in call for call in calls))
                
    def test_main_add_command(self):
        """Test main function with add command"""
        # First create a notebook
        notebook_path = os.path.join(self.test_dir, "test.ipynb")
        jupyter_controller.create_notebook(notebook_path)
        
        cells_json = json.dumps([{'type': 'markdown', 'content': '# Test'}])
        
        with patch('sys.argv', ['jupyter_controller.py', 'add', 'test', cells_json]):
            with patch('builtins.print') as mock_print:
                jupyter_controller.main()
                
                # Verify cells were added
                nb = jupyter_controller.read_notebook(notebook_path)
                self.assertEqual(len(nb['cells']), 1)


class TestJupyterControllerIntegration(unittest.TestCase):
    """Integration tests that test the full command-line interface"""
    
    def setUp(self):
        """Set up test environment"""
        self.test_dir = tempfile.mkdtemp()
        # Create a mock /monadic/data directory
        self.data_dir = os.path.join(self.test_dir, 'monadic', 'data')
        os.makedirs(self.data_dir, exist_ok=True)
        
        # Patch the base path
        self.patcher = patch('jupyter_controller.get_notebook_path', 
                           lambda x: os.path.join(self.data_dir, x if x.endswith('.ipynb') else f"{x}.ipynb"))
        self.patcher2 = patch('jupyter_controller.get_json_path',
                            lambda x: os.path.join(self.data_dir, x if x.endswith('.json') else f"{x}.json"))
        self.patcher.start()
        self.patcher2.start()
        
    def tearDown(self):
        """Clean up"""
        self.patcher.stop()
        self.patcher2.stop()
        shutil.rmtree(self.test_dir)
        
    def test_full_workflow(self):
        """Test a complete workflow: create, add, update, search, delete"""
        # Create notebook
        with patch('sys.argv', ['jupyter_controller.py', 'create', 'workflow_test']):
            jupyter_controller.main()
            
        # Find the created notebook (it will have a timestamp)
        notebooks = [f for f in os.listdir(self.data_dir) if f.startswith('workflow_test_') and f.endswith('.ipynb')]
        self.assertEqual(len(notebooks), 1)
        notebook_name = notebooks[0].replace('.ipynb', '')
        
        # Add cells
        cells_json = json.dumps([
            {'type': 'markdown', 'content': '# Workflow Test'},
            {'type': 'code', 'content': 'import numpy as np\ndata = np.array([1, 2, 3])'}
        ])
        
        with patch('sys.argv', ['jupyter_controller.py', 'add', notebook_name, cells_json]):
            jupyter_controller.main()
            
        # Search for content
        with patch('sys.argv', ['jupyter_controller.py', 'search', notebook_name, 'numpy']):
            with patch('builtins.print') as mock_print:
                jupyter_controller.main()
                calls = [str(call) for call in mock_print.call_args_list]
                self.assertTrue(any('numpy' in call for call in calls))
                
        # Update cell
        with patch('sys.argv', ['jupyter_controller.py', 'update', notebook_name, '0', '# Updated Title', 'markdown']):
            jupyter_controller.main()
            
        # Delete cell
        with patch('sys.argv', ['jupyter_controller.py', 'delete', notebook_name, '1']):
            jupyter_controller.main()
            
        # Verify final state
        notebook_path = os.path.join(self.data_dir, f"{notebook_name}.ipynb")
        nb = jupyter_controller.read_notebook(notebook_path)
        self.assertEqual(len(nb['cells']), 1)
        self.assertEqual(nb['cells'][0]['source'], '# Updated Title')


if __name__ == '__main__':
    unittest.main()