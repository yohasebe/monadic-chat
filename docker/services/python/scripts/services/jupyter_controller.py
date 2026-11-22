#!/usr/bin/env python
# -*- coding: utf-8 -*-

import os
import sys
import stat
import argparse
import tempfile
import nbformat as nbf
from datetime import datetime
import json
import time
import random
import errno
import socket

def get_notebook_path(filename):
    notebook_path = f"/monadic/data/{filename}"
    if not notebook_path.endswith('.ipynb'):
        notebook_path += '.ipynb'
    return notebook_path

def get_json_path(filename):
    json_path = f"/monadic/data/{filename}"
    if not json_path.endswith('.json'):
        json_path += '.json'
    return json_path

def notebook_exists(notebook_path):
    return os.path.exists(notebook_path)

def read_notebook(notebook_path, max_retries=5, retry_delay=1):
    for attempt in range(max_retries):
        try:
            with open(notebook_path, 'r', encoding='utf-8') as f:
                nb = nbf.read(f, as_version=4)
                if not isinstance(nb, dict) or 'cells' not in nb:
                    raise ValueError("Invalid notebook structure")
                return nb
        except Exception as e:
            print(f"Error reading notebook: {str(e)}")
            if attempt == max_retries - 1:
                raise
            else:
                time.sleep(retry_delay + random.uniform(0, 1))
    raise IOError(f"Failed to read notebook at {notebook_path} after {max_retries} attempts")

def write_notebook(notebook_path, nb, max_retries=5, retry_delay=1):
    # Written to a file beside it and put in its place, so that a reader
    # never finds half a notebook.
    directory = os.path.dirname(notebook_path) or '.'
    for attempt in range(max_retries):
        temp_path = None
        try:
            fd, temp_path = tempfile.mkstemp(prefix='.', suffix='.ipynb.tmp', dir=directory)
            with os.fdopen(fd, 'w', encoding='utf-8') as f:
                nbf.write(nb, f)
            try:
                os.chmod(temp_path, stat.S_IMODE(os.lstat(notebook_path).st_mode))
            except FileNotFoundError:
                os.chmod(temp_path, 0o644)
            os.replace(temp_path, notebook_path)
            return
        except Exception as e:
            if temp_path and os.path.exists(temp_path):
                os.remove(temp_path)
            print(f"Error writing notebook: {str(e)}")
            if attempt == max_retries - 1:
                raise
            else:
                time.sleep(retry_delay + random.uniform(0, 1))
    raise IOError(f"Failed to write notebook at {notebook_path} after {max_retries} attempts")

def create_notebook(notebook_path):
    nb = nbf.v4.new_notebook()
    write_notebook(notebook_path, nb)
    print(f"Notebook created at {notebook_path}")
    # Verify the file was actually created
    if os.path.exists(notebook_path):
        print(f"[DEBUG] File verified to exist: {notebook_path}")
    else:
        print(f"[ERROR] File was NOT created: {notebook_path}")

def new_cell(cell):
    """A notebook cell from a cell given as {type|cell_type, content|source}."""
    if not isinstance(cell, dict):
        raise ValueError("Each cell must be an object")
    # Support both 'type' and 'cell_type' fields
    cell_type = cell.get('type') or cell.get('cell_type')
    # Support both 'content' and 'source' fields
    content = cell.get('content')
    if content is None:
        source = cell.get('source', '')
        # If source is a list, join it
        if isinstance(source, list):
            # Remove trailing newlines from each line before joining
            # This prevents double newlines when lines already have \n
            cleaned_lines = []
            for line in source:
                if isinstance(line, str) and line.endswith('\n'):
                    cleaned_lines.append(line.rstrip('\n'))
                else:
                    cleaned_lines.append(line)
            content = '\n'.join(cleaned_lines)
        else:
            content = source

    if cell_type == 'markdown':
        return nbf.v4.new_markdown_cell(content)
    elif cell_type == 'code':
        return nbf.v4.new_code_cell(content)
    raise ValueError(f"Invalid cell type: {cell_type}")

def add_cells_to_notebook(notebook_path, new_cells, max_retries=5, retry_delay=1):
    for attempt in range(max_retries):
        try:
            nb = read_notebook(notebook_path)
            for cell in new_cells:
                nb['cells'].append(new_cell(cell))
            write_notebook(notebook_path, nb)
            print(f"Cells added to notebook at {notebook_path}")
            return
        except Exception as e:
            print(f"Error occurred: {str(e)}")
            if attempt == max_retries - 1:
                raise
            else:
                time.sleep(retry_delay + random.uniform(0, 1))
    print(f"Failed to add cells to notebook at {notebook_path} after {max_retries} attempts")

class NotebookChanged(Exception):
    """The notebook was saved by someone else while it was being changed."""

def file_state(notebook_path):
    st = os.stat(notebook_path)
    return (st.st_ino, st.st_mtime_ns, st.st_size)

def save_unless_changed(notebook_path, nb, state):
    if file_state(notebook_path) != state:
        raise NotebookChanged("The notebook was saved by another program meanwhile; read it again and retry")
    write_notebook(notebook_path, nb)

def move_cell(notebook_path, from_index, to_index):
    """Moves a cell so that it ends at to_index (both 0-based, of the cells
    as they are). The cell keeps its id, metadata and outputs."""
    state = file_state(notebook_path)
    nb = read_notebook(notebook_path)
    count = len(nb['cells'])
    if count == 0:
        raise IndexError("The notebook has no cells")
    for name, value in (('from_index', from_index), ('to_index', to_index)):
        if not 0 <= value < count:
            raise IndexError(f"{name} {value} is out of range: the notebook has {count} cells (0 to {count - 1})")
    if from_index != to_index:
        cell = nb['cells'].pop(from_index)
        nb['cells'].insert(to_index, cell)
        save_unless_changed(notebook_path, nb, state)
    return count

def insert_cells(notebook_path, index, cells):
    """Inserts cells before the cell at index (0-based); index equal to the
    number of cells adds them at the end."""
    if not isinstance(cells, list) or not cells:
        raise ValueError("Cells must be a non-empty array")
    state = file_state(notebook_path)
    nb = read_notebook(notebook_path)
    count = len(nb['cells'])
    if not 0 <= index <= count:
        raise IndexError(f"index {index} is out of range: the notebook has {count} cells (0 to {count})")
    made = [new_cell(cell) for cell in cells]
    with_ids = nb.get('nbformat', 4) > 4 or nb.get('nbformat_minor', 0) >= 5
    taken = {cell.get('id') for cell in nb['cells']}
    for cell in made:
        if not with_ids:
            cell.pop('id', None)
            continue
        while cell.get('id') in taken:
            cell['id'] = nbf.v4.new_code_cell().get('id')
        taken.add(cell['id'])
    nb['cells'][index:index] = made
    save_unless_changed(notebook_path, nb, state)
    return len(made)

def display_notebook_cells(notebook_path):
    nb = read_notebook(notebook_path)
    for i, cell in enumerate(nb['cells']):
        cell_type = cell['cell_type']
        content = cell['source']
        print(f"Cell {i} - Type: {cell_type}\n{content}\n{'-'*40}")

def delete_cell(notebook_path, index, max_retries=5, retry_delay=1):
    for attempt in range(max_retries):
        try:
            nb = read_notebook(notebook_path)
            if 0 <= index < len(nb['cells']):
                del nb['cells'][index]
                write_notebook(notebook_path, nb)
                print(f"Cell {index} deleted from notebook at {notebook_path}")
                return
            else:
                print(f"Index {index} is out of range")
                return
        except Exception as e:
            print(f"Error deleting cell: {str(e)}")
            if attempt == max_retries - 1:
                raise
            else:
                time.sleep(retry_delay + random.uniform(0, 1))
    raise IOError(f"Failed to delete cell from notebook at {notebook_path} after {max_retries} attempts")

def update_cell(notebook_path, index, new_content, cell_type='markdown', max_retries=5, retry_delay=1):
    for attempt in range(max_retries):
        try:
            nb = read_notebook(notebook_path)
            if 0 <= index < len(nb['cells']):
                if cell_type == 'markdown':
                    nb['cells'][index] = nbf.v4.new_markdown_cell(new_content)
                elif cell_type == 'code':
                    nb['cells'][index] = nbf.v4.new_code_cell(new_content)
                else:
                    raise ValueError(f"Invalid cell type: {cell_type}")
                write_notebook(notebook_path, nb)
                print(f"Cell {index} updated in notebook at {notebook_path}")
                return
            else:
                print(f"Index {index} is out of range")
                return
        except Exception as e:
            print(f"Error updating cell: {str(e)}")
            if attempt == max_retries - 1:
                raise
            else:
                time.sleep(retry_delay + random.uniform(0, 1))
    raise IOError(f"Failed to update cell in notebook at {notebook_path} after {max_retries} attempts")

def search_cells(notebook_path, keyword):
    nb = read_notebook(notebook_path)
    results = [(i, cell['cell_type'], cell['source']) for i, cell in enumerate(nb['cells']) if keyword in cell['source']]
    return results

def main():
    parser = argparse.ArgumentParser(description="Jupyter Notebook Controller")
    subparsers = parser.add_subparsers(dest='command')

    create_parser = subparsers.add_parser('create', help='Create a new Jupyter notebook')
    create_parser.add_argument('filename', type=str, nargs='?', help='Name of the notebook file to create')

    read_parser = subparsers.add_parser('read', help='Read a Jupyter notebook')
    read_parser.add_argument('filename', type=str, help='Name of the notebook file to read')

    add_parser = subparsers.add_parser('add', help='Add cells to a Jupyter notebook')
    add_parser.add_argument('filename', type=str, help='Name of the notebook file to add cells to')
    add_parser.add_argument('cells', type=str, help='JSON string of cells to add')

    display_parser = subparsers.add_parser('display', help='Display the contents of a Jupyter notebook')
    display_parser.add_argument('filename', type=str, help='Name of the notebook file to display')

    delete_parser = subparsers.add_parser('delete', help='Delete a cell from a Jupyter notebook')
    delete_parser.add_argument('filename', type=str, help='Name of the notebook file to delete a cell from')
    delete_parser.add_argument('index', type=int, help='Index of the cell to delete')

    update_parser = subparsers.add_parser('update', help='Update a cell in a Jupyter notebook')
    update_parser.add_argument('filename', type=str, help='Name of the notebook file to update a cell in')
    update_parser.add_argument('index', type=int, help='Index of the cell to update')
    update_parser.add_argument('content', type=str, help='New content for the cell')
    update_parser.add_argument('cell_type', type=str, choices=['markdown', 'code'], help='Type of the cell (markdown or code)')

    search_parser = subparsers.add_parser('search', help='Search for a keyword in a Jupyter notebook')
    search_parser.add_argument('filename', type=str, help='Name of the notebook file to search in')
    search_parser.add_argument('keyword', type=str, help='Keyword to search for')

    add_from_json_parser = subparsers.add_parser('add_from_json', help='Add cells to a Jupyter notebook from a JSON file')
    add_from_json_parser.add_argument('notebook_filename', type=str, help='Name of the notebook file to add cells to')
    add_from_json_parser.add_argument('json_filename', type=str, help='Name of the JSON file containing cells to add')

    move_parser = subparsers.add_parser('move', help='Move a cell to another position')
    move_parser.add_argument('filename', type=str, help='Name of the notebook file')
    move_parser.add_argument('from_index', type=int, help='Index of the cell to move')
    move_parser.add_argument('to_index', type=int, help='Index the cell ends at')

    insert_parser = subparsers.add_parser('insert', help='Insert cells at a position')
    insert_parser.add_argument('filename', type=str, help='Name of the notebook file')
    insert_parser.add_argument('index', type=int, help='Index the first new cell takes')
    insert_parser.add_argument('cells', type=str, help='JSON string of cells to insert')

    args = parser.parse_args()

    # These say what failed on stderr and end with status 1.
    if args.command in ('move', 'insert'):
        notebook_path = get_notebook_path(args.filename)
        try:
            if not os.path.isfile(notebook_path):
                raise FileNotFoundError(f"Notebook {args.filename} does not exist")
            if args.command == 'move':
                move_cell(notebook_path, args.from_index, args.to_index)
                if args.from_index == args.to_index:
                    print(f"Cell {args.from_index} is already at that position")
                else:
                    print(f"Moved cell {args.from_index} to position {args.to_index}")
            else:
                count = insert_cells(notebook_path, args.index, json.loads(args.cells))
                print(f"Inserted {count} cell(s) at position {args.index}")
        except (OSError, ValueError, IndexError, NotebookChanged) as e:
            print(f"Error: {e}", file=sys.stderr)
            sys.exit(1)
        return


    try:
        if args.command == 'create':
            if args.filename:
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                notebook_filename = f"{args.filename}_{timestamp}.ipynb"
                notebook_path = get_notebook_path(notebook_filename)
            else:
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                notebook_filename = f"notebook_{timestamp}.ipynb"
                notebook_path = get_notebook_path(notebook_filename)
            
            if notebook_exists(notebook_path):
                # Return same success format so the model treats existing
                # notebooks identically to newly created ones (no retry loop).
                print(f"Notebook created: {notebook_filename}")
            else:
                create_notebook(notebook_path)
                # Just return the notebook filename, Ruby side will construct the full URL
                print(f"Notebook created: {notebook_filename}")

        elif args.command == 'read':
            notebook_path = get_notebook_path(args.filename)
            if notebook_exists(notebook_path):
                nb = read_notebook(notebook_path)
                print(nb)
            else:
                print(f"File {notebook_path} does not exist.")

        elif args.command == 'add':
            notebook_path = get_notebook_path(args.filename)
            if notebook_exists(notebook_path):
                new_cells = json.loads(args.cells)
                add_cells_to_notebook(notebook_path, new_cells)
            else:
                print(f"File {notebook_path} does not exist.")

        elif args.command == 'display':
            notebook_path = get_notebook_path(args.filename)
            if notebook_exists(notebook_path):
                display_notebook_cells(notebook_path)
            else:
                print(f"File {notebook_path} does not exist.")

        elif args.command == 'delete':
            notebook_path = get_notebook_path(args.filename)
            if notebook_exists(notebook_path):
                delete_cell(notebook_path, args.index)
            else:
                print(f"File {notebook_path} does not exist.")

        elif args.command == 'update':
            notebook_path = get_notebook_path(args.filename)
            if notebook_exists(notebook_path):
                update_cell(notebook_path, args.index, args.content, args.cell_type)
            else:
                print(f"File {notebook_path} does not exist.")

        elif args.command == 'search':
            notebook_path = get_notebook_path(args.filename)
            if notebook_exists(notebook_path):
                results = search_cells(notebook_path, args.keyword)
                for index, cell_type, content in results:
                    print(f"Found keyword in Cell {index} - Type: {cell_type}\n{content}\n{'-'*40}")
            else:
                print(f"File {notebook_path} does not exist.")

        elif args.command == 'add_from_json':
            notebook_path = get_notebook_path(args.notebook_filename)
            json_path = get_json_path(args.json_filename)
            if notebook_exists(notebook_path) and os.path.exists(json_path):
                with open(json_path, 'r', encoding='utf-8') as f:
                    new_cells = json.load(f)
                add_cells_to_notebook(notebook_path, new_cells)
            else:
                if not notebook_exists(notebook_path):
                    print(f"File {notebook_path} does not exist.")
                if not os.path.exists(json_path):
                    print(f"File {json_path} does not exist.")

    except IOError as e:
        print(f"An IO error occurred: {str(e)}")
    except ValueError as e:
        print(f"Invalid input: {str(e)}")
    except Exception as e:
        print(f"An unexpected error occurred: {str(e)}")

if __name__ == '__main__':
    main()

