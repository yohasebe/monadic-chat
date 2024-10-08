#!/usr/bin/env python

import argparse
import json
import os
import fitz  # PyMuPDF

def extract_text(pdf_path, output_format, all_pages):
    doc = fitz.open(pdf_path)
    
    for page in doc:
        if output_format == 'text':
            text = page.get_text()
        elif output_format == 'html':
            text = page.get_text("html")
        elif output_format == 'xml':
            text = page.get_text("xml")
        
        if all_pages:
            continue
        else:
            yield text
    
    if all_pages:
        if output_format == 'text':
            yield "\n".join([page.get_text() for page in doc])
        elif output_format == 'html':
            yield "\n".join([page.get_text("html") for page in doc])
        elif output_format == 'xml':
            yield "\n".join([page.get_text("xml") for page in doc])
    
    doc.close()

def export_as_json(pdf_path, output_format, all_pages):
    data = {'pages': []}
    try:
        for page_text in extract_text(pdf_path, output_format, all_pages):
            data['pages'].append({
                'text': page_text.strip()
            })
        json_data = json.dumps(data, ensure_ascii=False, indent=4)
        print(json_data)

        # Save the JSON data to a file
        base_filename = os.path.splitext(os.path.basename(pdf_path))[0]
        output_filename = f"{base_filename}.{output_format}.json"
        with open(output_filename, 'w', encoding='utf-8') as f:
            f.write(json_data)

        # Uncomment the line below if you want to print the output filename
        # print(f"Output saved to {output_filename}")

    except Exception as e:
        print(f"An error occurred: {e}")

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="Extract text from a PDF file and output as JSON.")
    parser.add_argument("pdf_path", help="Path to the PDF file")
    parser.add_argument("--format", choices=['text', 'html', 'xml'], default='text', help="Output format (text, html, xml)")
    parser.add_argument("--all-pages", action="store_true", help="Combine all pages into a single output")
    args = parser.parse_args()

    if not os.path.exists(args.pdf_path):
        print(f"The specified PDF file could not be found: {args.pdf_path}")
    else:
        export_as_json(args.pdf_path, args.format, args.all_pages)
