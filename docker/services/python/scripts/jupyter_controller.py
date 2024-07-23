#!/usr/bin/env python
# -*- coding: utf-8 -*-

import os
import argparse
import nbformat as nbf
from datetime import datetime
import json

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

def read_notebook(notebook_path):
    with open(notebook_path, 'r', encoding='utf-8') as f:
        return nbf.read(f, as_version=4)

def write_notebook(notebook_path, nb):
    with open(notebook_path, 'w', encoding='utf-8') as f:
        nbf.write(nb, f)

def create_notebook(notebook_path):
    nb = nbf.v4.new_notebook()
    text = "### Your Jupyterlab Notebook"
    code = "%pylab inline\nhist(normal(size=2000), bins=50);"
    nb['cells'] = [nbf.v4.new_markdown_cell(text), nbf.v4.new_code_cell(code)]
    write_notebook(notebook_path, nb)
    print(f"Notebook created at {notebook_path}")

def add_cells_to_notebook(notebook_path, new_cells):
    nb = read_notebook(notebook_path)
    for cell in new_cells:
        if cell['type'] == 'markdown':
            nb['cells'].append(nbf.v4.new_markdown_cell(cell['content']))
        elif cell['type'] == 'code':
            nb['cells'].append(nbf.v4.new_code_cell(cell['content']))
    write_notebook(notebook_path, nb)
    print(f"Cells added to notebook at {notebook_path}")

def display_notebook_cells(notebook_path):
    nb = read_notebook(notebook_path)
    for i, cell in enumerate(nb['cells']):
        cell_type = cell['cell_type']
        content = cell['source']
        print(f"Cell {i} - Type: {cell_type}\n{content}\n{'-'*40}")

def delete_cell(notebook_path, index):
    nb = read_notebook(notebook_path)
    if 0 <= index < len(nb['cells']):
        del nb['cells'][index]
        write_notebook(notebook_path, nb)
        print(f"Cell {index} deleted from notebook at {notebook_path}")
    else:
        print(f"Index {index} is out of range")

def update_cell(notebook_path, index, new_content, cell_type='markdown'):
    nb = read_notebook(notebook_path)
    if 0 <= index < len(nb['cells']):
        if cell_type == 'markdown':
            nb['cells'][index] = nbf.v4.new_markdown_cell(new_content)
        elif cell_type == 'code':
            nb['cells'][index] = nbf.v4.new_code_cell(new_content)
        write_notebook(notebook_path, nb)
        print(f"Cell {index} updated in notebook at {notebook_path}")
    else:
        print(f"Index {index} is out of range")

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

    args = parser.parse_args()

    if args.command == 'create':
        if args.filename:
            notebook_path = get_notebook_path(args.filename)
        else:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            notebook_path = get_notebook_path(f"notebook_{timestamp}")
        
        if notebook_exists(notebook_path):
            print(f"File {notebook_path} already exists.")
        else:
            create_notebook(notebook_path)

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

if __name__ == '__main__':
    main()

