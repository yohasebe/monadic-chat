#!/usr/bin/env python

import sys
import argparse
import json
import os
from typing import Iterator
import fitz        # PyMuPDF
import pymupdf4llm # PyMuPDF4LLM

def extract_text(pdf_path: str, output_format: str, all_pages: bool, show_progress: bool = False) -> Iterator[str]:
    """
    Extract text from PDF file in specified format.
    
    Args:
        pdf_path: Path to the PDF file
        output_format: Output format ('md', 'txt', 'html', 'xml')
        all_pages: If True, combine all pages into single output
        show_progress: Show progress bar for markdown format (default: False)
    
    Yields:
        str: Extracted text in specified format
    
    Raises:
        fitz.FileDataError: If the PDF file is corrupted or invalid
        FileNotFoundError: If the PDF file does not exist
        ValueError: If the output format is invalid
    """
    if not os.path.exists(pdf_path):
        raise FileNotFoundError(f"PDF file not found: {pdf_path}")

    if output_format not in ['markdown', 'md', 'txt', 'html', 'xml']:
        raise ValueError(f"Invalid output format: {output_format}")

    if output_format in ['markdown', 'md']:
        doc = fitz.open(pdf_path)
        try:
            if all_pages:
                # Process all pages at once
                md_text = pymupdf4llm.to_markdown(
                    doc,
                    show_progress=show_progress,
                    force_text=True,
                    table_strategy='lines'
                )
                if isinstance(md_text, list):
                    # Handle case when page_chunks=True
                    yield '\n'.join(chunk['text'] for chunk in md_text)
                else:
                    yield md_text
            else:
                # Process pages individually
                for page_num in range(len(doc)):
                    md_text = pymupdf4llm.to_markdown(
                        doc,
                        pages=[page_num],
                        show_progress=False,
                        force_text=True
                    )
                    if isinstance(md_text, list):
                        yield md_text[0]['text']
                    else:
                        yield md_text
        finally:
            doc.close()
    else:
        doc = fitz.open(pdf_path)
        try:
            if all_pages:
                if output_format == 'txt':
                    yield "\n".join([page.get_text() for page in doc])
                elif output_format == 'html':
                    yield "\n".join([page.get_text("html") for page in doc])
                elif output_format == 'xml':
                    yield "\n".join([page.get_text("xml") for page in doc])
            else:
                for page in doc:
                    if output_format == 'txt':
                        yield page.get_text()
                    elif output_format == 'html':
                        yield page.get_text("html")
                    elif output_format == 'xml':
                        yield page.get_text("xml")
        finally:
            doc.close()

def export_as_json(pdf_path: str, output_format: str, all_pages: bool, show_progress: bool = False) -> None:
    """
    Export extracted text as JSON.
    
    Args:
        pdf_path: Path to the PDF file
        output_format: Output format ('md', 'txt', 'html', 'xml')
        all_pages: If True, combine all pages into single output
        show_progress: Show progress bar for markdown format (default: False)
    
    Raises:
        Exception: If any error occurs during processing
    """
    data = {'pages': []}
    try:
        for page_text in extract_text(pdf_path, output_format, all_pages, show_progress):
            data['pages'].append({
                'text': page_text.strip()
            })
        
        # Save the JSON data to a file
        base_filename = os.path.splitext(os.path.basename(pdf_path))[0]
        output_filename = f"{base_filename}.{output_format}.json"
        
        json_data = json.dumps(data, ensure_ascii=False, indent=4)
        with open(output_filename, 'w', encoding='utf-8') as f:
            f.write(json_data)
            
        # Print the JSON data to stdout
        print(json_data)

    except Exception as e:
        print(f"Error processing PDF: {str(e)}")
        raise

def main() -> None:
    """
    Main function to handle command line arguments and process PDF file.
    
    Raises:
        SystemExit: If the program encounters an error
    """
    parser = argparse.ArgumentParser(
        description="Extract text from a PDF file and output as JSON."
    )
    parser.add_argument(
        "pdf_path",
        help="Path to the PDF file"
    )
    parser.add_argument(
        "--format",
        choices=['md', 'txt', 'html', 'xml'],
        default='md',
        help="Output format (md, txt, html, xml)"
    )
    parser.add_argument(
        "--all-pages",
        action="store_true",
        help="Combine all pages into a single output"
    )
    parser.add_argument(
        "--show-progress",
        action="store_true",
        help="Enable progress bar (markdown format only)"
    )

    args = parser.parse_args()

    try:
        export_as_json(
            args.pdf_path,
            args.format,
            args.all_pages,
            show_progress=args.show_progress
        )
    except Exception as e:
        print(f"Error: {str(e)}")
        sys.exit(1)

if __name__ == '__main__':
    main()
