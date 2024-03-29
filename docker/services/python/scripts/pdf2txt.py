#!/usr/bin/env python

import argparse
import json
import os
import re
from io import StringIO, BytesIO
from pdfminer.high_level import extract_text_to_fp
from pdfminer.layout import LAParams
from pdfminer.pdfinterp import PDFResourceManager, PDFPageInterpreter
from pdfminer.pdfpage import PDFPage
from pdfminer.converter import TextConverter, HTMLConverter, XMLConverter

def extract_text(pdf_path, output_format, all_pages):
    rsrcmgr = PDFResourceManager()
    laparams = LAParams()
    if output_format == 'text':
        codec = 'utf-8'
        output = StringIO()
        device = TextConverter(rsrcmgr, output, codec=codec, laparams=laparams)
    else:
        output = BytesIO()
        if output_format == 'html':
            device = HTMLConverter(rsrcmgr, output, codec='utf-8', laparams=laparams)
        elif output_format == 'xml':
            device = XMLConverter(rsrcmgr, output, codec='utf-8', laparams=laparams)

    with open(pdf_path, 'rb') as fp:
        interpreter = PDFPageInterpreter(rsrcmgr, device)
        for page in PDFPage.get_pages(fp):
            interpreter.process_page(page)
            if all_pages:
                continue
            else:
                text = output.getvalue()
                if output_format != 'text':
                    text = text.decode('utf-8')
                yield text
                output.truncate(0)
                output.seek(0)

    text = output.getvalue()
    if output_format != 'text':
        text = text.decode('utf-8')
    device.close()
    output.close()
    if all_pages:
        yield text

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
