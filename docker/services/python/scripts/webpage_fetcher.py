#!/usr/bin/env python

import sys
import time
import argparse
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.common.exceptions import WebDriverException, TimeoutException
import os
from datetime import datetime
from urllib.parse import urlparse
from PIL import Image
from bs4 import BeautifulSoup
import json
from bs4.element import Comment

def is_valid_url(url):
    """
    Validate if the given string is a proper URL
    Args:
        url (str): URL string to validate
    Returns:
        bool: True if valid URL, False otherwise
    """
    try:
        result = urlparse(url)
        return bool(result.netloc)
    except ValueError:
        return False

def ensure_scheme(url):
    """
    Add https:// scheme if no scheme is present in the URL
    Args:
        url (str): URL string to check
    Returns:
        str: URL with scheme
    """
    if not urlparse(url).scheme:
        url = "https://" + url
    return url

def is_wikipedia_page(url):
    """
    Check if the given URL is a Wikipedia page
    Args:
        url (str): URL to check
    Returns:
        bool: True if Wikipedia page, False otherwise
    """
    parsed_url = urlparse(url)
    return any(domain in parsed_url.netloc 
              for domain in ['wikipedia.org', 'wikipedia.com'])

def generate_filename(url, mode, element=None):
    """
    Generate a filename based on URL, mode, and optional element
    Args:
        url (str): Target URL
        mode (str): Output mode (png/md)
        element (str, optional): CSS selector of the target element
    Returns:
        str: Generated filename
    """
    # Parse URL to get domain
    parsed_url = urlparse(url)
    domain = parsed_url.netloc.replace('www.', '')
    
    # Create timestamp
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    
    # Generate base filename
    base_filename = f"{domain}_{timestamp}"
    
    # Add element information if specified
    if element:
        # Clean up element selector for filename
        clean_element = element.replace('#', 'id_').replace('.', 'class_')
        clean_element = ''.join(c if c.isalnum() or c == '_' else '_' for c in clean_element)
        base_filename = f"{base_filename}_{clean_element}"
    
    # Add mode extension
    filename = f"{base_filename}.{mode}"
    
    # Ensure filename is valid and not too long
    if len(filename) > 255:  # Maximum filename length in most filesystems
        max_base_length = 255 - len(f"_{timestamp}.{mode}")
        truncated_domain = domain[:max_base_length]
        filename = f"{truncated_domain}_{timestamp}.{mode}"
    
    return filename

def generate_output_path(base_dir, url, mode, element=None):
    """
    Generate output path for saving files
    Args:
        base_dir (str): Base directory path
        url (str): Target URL
        mode (str): Output mode (png/md)
        element (str, optional): CSS selector of the target element
    Returns:
        tuple: (str: full output path, str: created directory path)
    """
    # Create absolute path for base directory
    output_dir = os.path.abspath(base_dir)
    
    # Create directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)
    
    # Generate filename
    filename = generate_filename(url, mode, element)
    
    # Combine directory and filename
    output_path = os.path.join(output_dir, filename)
    
    return output_path, output_dir

def create_driver_options(args):
    """
    Configure and create Chrome options
    Args:
        args: Command line arguments
    Returns:
        Options: Configured Chrome options
    """
    options = Options()
    options.add_argument('--headless')
    options.add_argument('--disable-gpu')
    options.add_argument('--disable-dev-shm-usage')
    options.add_argument('--no-sandbox')
    options.add_argument('--start-maximized')
    
    # Enable images only for PNG mode
    if args.mode == 'png':
        options.add_argument('--window-size=1920,1080')
    else:
        # Disable images for text extraction to improve performance
        options.add_argument('--blink-settings=imagesEnabled=false')
    
    return options

def take_full_page_screenshot(driver, output_path):
    """
    Take a screenshot of the entire page with optimized waiting
    Args:
        driver: Selenium WebDriver instance
        output_path: Path to save the screenshot
    """
    # Wait for page to be completely loaded
    WebDriverWait(driver, 10).until(
        lambda d: d.execute_script("return document.readyState") == "complete"
    )
    
    # Wait for dynamic content
    time.sleep(2)
    
    # Get the total height of the page
    total_height = driver.execute_script("""
        return Math.max(
            document.documentElement.scrollHeight,
            document.documentElement.offsetHeight
        );
    """)
    
    # Get viewport dimensions
    viewport_width = driver.execute_script("return window.innerWidth")
    viewport_height = driver.execute_script("return window.innerHeight")
    
    # Set window size to capture everything
    driver.set_window_size(viewport_width, total_height)
    
    # Wait for layout to stabilize
    time.sleep(1)
    
    # Take the screenshot
    driver.save_screenshot(output_path)
    
    # Reset window size
    driver.set_window_size(viewport_width, viewport_height)

def extract_metadata(soup):
    """
    Extract metadata from the webpage
    Args:
        soup: BeautifulSoup object of the page
    Returns:
        dict: Dictionary containing metadata
    """
    metadata = {
        'title': '',
        'description': '',
        'keywords': '',
        'author': '',
        'og_tags': {},
        'twitter_cards': {},
        'other_meta': {}
    }

    # Extract title
    title_tag = soup.find('title')
    if title_tag:
        metadata['title'] = title_tag.string.strip()

    # Process meta tags
    for meta in soup.find_all('meta'):
        # Get the meta tag attributes
        name = meta.get('name', '').lower()
        property = meta.get('property', '').lower()
        content = meta.get('content', '')

        if name == 'description':
            metadata['description'] = content
        elif name == 'keywords':
            metadata['keywords'] = content
        elif name == 'author':
            metadata['author'] = content
        elif property.startswith('og:'):
            metadata['og_tags'][property[3:]] = content
        elif property.startswith('twitter:'):
            metadata['twitter_cards'][property[8:]] = content
        elif name and content:
            metadata['other_meta'][name] = content

    return metadata

def remove_comments(soup):
    """
    Remove all comment nodes from the BeautifulSoup object
    Args:
        soup: BeautifulSoup object
    """
    for comment in soup.find_all(text=lambda text: isinstance(text, Comment)):
        comment.extract()

def process_element(elem, keep_unknown=False):
    """
    Process individual element and its children
    Args:
        elem: BeautifulSoup element
        keep_unknown (bool): Whether to keep text content of unknown elements
    Returns:
        str: Processed text content
    """
    if isinstance(elem, str):
        return elem.strip()
    
    # Define meaningful content elements with their formatting rules
    content_elements = {
        # Text content elements
        'p': {'prefix': '\n', 'suffix': '\n'},
        'span': {'prefix': '', 'suffix': ' '},
        'a': {'prefix': '', 'suffix': ' '},
        'text': {'prefix': '', 'suffix': ' '},
        
        # Headings
        'h1': {'prefix': '\n# ', 'suffix': '\n'},
        'h2': {'prefix': '\n## ', 'suffix': '\n'},
        'h3': {'prefix': '\n### ', 'suffix': '\n'},
        'h4': {'prefix': '\n#### ', 'suffix': '\n'},
        'h5': {'prefix': '\n##### ', 'suffix': '\n'},
        'h6': {'prefix': '\n###### ', 'suffix': '\n'},
        
        # Lists
        'ul': {'prefix': '\n', 'suffix': '\n'},
        'ol': {'prefix': '\n', 'suffix': '\n'},
        'li': {'prefix': '\n- ', 'suffix': ''},
        'dl': {'prefix': '\n', 'suffix': '\n'},
        'dt': {'prefix': '\n**', 'suffix': '**'},
        'dd': {'prefix': ': ', 'suffix': '\n'},
        
        # Quotes
        'blockquote': {'prefix': '\n> ', 'suffix': '\n'},
        'q': {'prefix': '"', 'suffix': '"'},
        'cite': {'prefix': '_', 'suffix': '_'},
        
        # Semantic sections
        'article': {'prefix': '\n', 'suffix': '\n'},
        'section': {'prefix': '\n', 'suffix': '\n'},
        'main': {'prefix': '\n', 'suffix': '\n'},
        'header': {'prefix': '\n', 'suffix': '\n'},
        'footer': {'prefix': '\n', 'suffix': '\n'},
        'nav': {'prefix': '\n', 'suffix': '\n'},
        'aside': {'prefix': '\n', 'suffix': '\n'},
        
        # Other content elements
        'div': {'prefix': '\n', 'suffix': '\n'},
        'pre': {'prefix': '\n```\n', 'suffix': '\n```\n'},
        'code': {'prefix': '`', 'suffix': '`'},
        'table': {'prefix': '\n', 'suffix': '\n'},
        'figure': {'prefix': '\n', 'suffix': '\n'},
        'figcaption': {'prefix': '_Figure: ', 'suffix': '_\n'}
    }
    
    # Define elements to be completely ignored
    ignored_elements = {
        # Scripts and styles
        'script', 'style', 'noscript',
        
        # Media elements
        'img', 'video', 'audio', 'svg', 'canvas',
        'picture', 'source',
        
        # Interactive elements
        'button', 'input', 'textarea', 'select',
        'option', 'form', 'iframe',
        
        # Other non-content elements
        'meta', 'link', 'br', 'hr', 'wbr',
        'template', 'slot', 'portal'
    }
    
    if elem.name in ignored_elements:
        return ''
        
    if elem.name in content_elements:
        format_rule = content_elements[elem.name]
        content = ' '.join(
            filter(None, [process_element(child, keep_unknown) for child in elem.children])
        ).strip()
        if content:
            return f"{format_rule['prefix']}{content}{format_rule['suffix']}"
        return ''
    
    # Handle unknown elements
    if keep_unknown:
        return ' '.join(
            filter(None, [process_element(child, keep_unknown) for child in elem.children])
        ).strip()
    return ''

def extract_wikipedia_content(soup, keep_unknown=False):
    """
    Extract content specifically from Wikipedia pages
    Args:
        soup: BeautifulSoup object of the page
        keep_unknown (bool): Whether to keep text content of unknown elements
    Returns:
        str: Formatted Wikipedia content
    """
    # Remove unwanted Wikipedia-specific elements
    unwanted_wiki_elements = [
        'div.mw-jump-link',           # Skip to navigation/content links
        'div.mw-editsection',         # Edit section links
        'div.navbox',                 # Navigation boxes at bottom
        'div.vertical-navbox',        # Vertical navigation boxes
        'div.sidebar',                # Sidebar elements
        'div.sistersitebox',          # Sister project links
        'div.metadata',               # Metadata boxes
        'table.metadata',             # Metadata tables
        'div.reflist',                # Reference lists
        'div.refbegin',               # Reference sections
        'div.mw-references-wrap',     # Reference wrappers
        'div#toc',                    # Table of contents
        'div.toc',                    # Alternative TOC
        'div.infobox',                # Infoboxes
        'table.infobox',              # Infobox tables
        'div.thumb',                  # Image thumbnails
        'div.mbox-small',             # Small message boxes
        'table.ambox',                # Article message boxes
        'div.sister-wikipedia',       # Sister Wikipedia project links
        'div.mw-authority-control'    # Authority control
    ]

    # Remove all unwanted elements
    for selector in unwanted_wiki_elements:
        for element in soup.select(selector):
            element.decompose()

    # Find the main content div
    content_div = soup.find('div', id='mw-content-text')
    if not content_div:
        return ""

    # Find the parser output div
    parser_output = content_div.find('div', class_='mw-parser-output')
    if not parser_output:
        return ""

    # Process content
    content = process_element(parser_output, keep_unknown)
    
    # Clean up the content
    lines = [line.strip() for line in content.split('\n')]
    cleaned_content = '\n'.join(filter(None, lines))
    
    return cleaned_content


def get_meaningful_content(driver, element=None, url=None, keep_unknown=False):
    """
    Extract meaningful content from the webpage while preserving basic structure
    Args:
        driver: Selenium WebDriver instance
        element: Optional specific element to extract from
        url: Original URL for special handling
        keep_unknown (bool): Whether to keep text content of unknown elements
    Returns:
        tuple: (str: Formatted text content, dict: Metadata)
    """
    # Get HTML content
    html = element.get_attribute('outerHTML') if element else driver.page_source
    soup = BeautifulSoup(html, 'html.parser')

    # Remove all HTML comments
    remove_comments(soup)

    # Extract metadata
    metadata = extract_metadata(soup)

    # Special handling for Wikipedia pages
    if url and is_wikipedia_page(url):
        return extract_wikipedia_content(soup, keep_unknown), metadata

    # Remove script and style elements
    for elem in soup.find_all(['script', 'style', 'noscript']):
        elem.decompose()

    # Find main content
    main_content = None
    content_selectors = [
        'main',
        'article',
        'div[role="main"]',
        '#main-content',
        '#content',
        '.content',
        '#main',
        '.main'
    ]

    for selector in content_selectors:
        main_content = soup.select_one(selector)
        if main_content:
            break

    if not main_content:
        main_content = soup.body

    # Extract and format content
    content = process_element(main_content, keep_unknown)

    # Clean up the formatted content
    lines = [line.strip() for line in content.split('\n')]
    cleaned_content = '\n'.join(filter(None, lines))
    
    return cleaned_content, metadata

def extract_text(driver, element=None, url=None, keep_unknown=False):
    """
    Extract and format text content from the webpage with optimized waiting
    Args:
        driver: Selenium WebDriver instance
        element: Optional specific element to extract from
        url: Original URL for special handling
        keep_unknown (bool): Whether to keep text content of unknown elements
    Returns:
        tuple: (str: Formatted text content, dict: Metadata)
    """
    try:
        # Wait for body element to be present
        WebDriverWait(driver, 10).until(
            EC.presence_of_element_located((By.TAG_NAME, 'body'))
        )
        
        # Wait for page load completion
        WebDriverWait(driver, 10).until(
            lambda d: d.execute_script("return document.readyState") == "complete"
        )
        
        # Extract meaningful content and metadata
        content, metadata = get_meaningful_content(driver, element, url, keep_unknown)
        
        if not content.strip():
            print("Warning: No content extracted from the page", file=sys.stderr)
        
        # Format metadata as markdown
        metadata_md = "\n## Metadata\n\n"
        if metadata['title']:
            metadata_md += f"### Title\n{metadata['title']}\n\n"
        if metadata['description']:
            metadata_md += f"### Description\n{metadata['description']}\n\n"
        if metadata['keywords']:
            metadata_md += f"### Keywords\n{metadata['keywords']}\n\n"
        if metadata['author']:
            metadata_md += f"### Author\n{metadata['author']}\n\n"
        
        if metadata['og_tags']:
            metadata_md += "### Open Graph Tags\n"
            for key, value in metadata['og_tags'].items():
                metadata_md += f"- {key}: {value}\n"
            metadata_md += "\n"
        
        if metadata['twitter_cards']:
            metadata_md += "### Twitter Cards\n"
            for key, value in metadata['twitter_cards'].items():
                metadata_md += f"- {key}: {value}\n"
            metadata_md += "\n"
        
        if metadata['other_meta']:
            metadata_md += "### Other Metadata\n"
            for key, value in metadata['other_meta'].items():
                metadata_md += f"- {key}: {value}\n"
            metadata_md += "\n"
        
        # Combine content and metadata
        full_content = f"{content}\n\n{metadata_md}"
        
        return full_content.strip(), metadata
        
    except Exception as e:
        print(f"Warning: Error during content extraction: {e}", file=sys.stderr)
        return "", {}

def create_parser():
    """
    Create and configure the argument parser
    Returns:
        argparse.ArgumentParser: Configured parser
    """
    parser = argparse.ArgumentParser(
        description='Web Page Content Fetcher - Capture webpage content as PNG or Markdown',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Capture full page as PNG to current directory
  %(prog)s --url example.com --mode png --fullpage true

  # Save PNG to specific directory
  %(prog)s --url example.com --mode png --filepath /path/to/screenshots

  # Capture specific element as PNG
  %(prog)s --url example.com --mode png --element "#main-content" --fullpage false

  # Save PNG and print text content with metadata
  %(prog)s --url example.com --mode png --print-text --save-metadata

  # Extract specific element as Markdown and output to stdout
  %(prog)s --url example.com --mode md --element "#main-content" --output stdout
  
  # Save page content as Markdown with metadata to specific directory
  %(prog)s --url example.com --mode md --filepath /path/to/output --save-metadata

  # Extract content including unknown elements
  %(prog)s --url example.com --mode md --keep-unknown
        """
    )

    # Required arguments
    parser.add_argument(
        '--url',
        type=str,
        required=True,
        help='Target URL to fetch (with or without https://)'
    )

    # Optional arguments
    parser.add_argument(
        '--mode',
        type=str,
        choices=['png', 'md'],
        default='md',
        help='Output mode: png for screenshot, md for markdown (default: md)'
    )

    parser.add_argument(
        '--output',
        type=str,
        choices=['file', 'stdout'],
        default='file',
        help='Output destination: file or stdout (default: file)'
    )

    parser.add_argument(
        '--filepath',
        type=str,
        default='./',
        help='Directory path for saving output files (default: current directory)'
    )

    parser.add_argument(
        '--element',
        type=str,
        help='CSS selector for the target element (e.g., "#content", ".main-text")'
    )

    parser.add_argument(
        '--fullpage',
        type=str,
        choices=['true', 'false'],
        default='false',
        help='Capture entire page as screenshot (PNG mode only, default: false)'
    )

    parser.add_argument(
        '--timeout-sec',
        type=int,
        default=30,
        help='Maximum wait time in seconds (default: 30)'
    )

    parser.add_argument(
        '--print-text',
        action='store_true',
        help='Print text content to stdout even in PNG mode'
    )

    parser.add_argument(
        '--keep-unknown',
        action='store_true',
        help='Keep text content from unknown HTML elements'
    )

    parser.add_argument(
        '--save-metadata',
        action='store_true',
        help='Save metadata as JSON file'
    )

    return parser

def main():
    """
    Main function to handle webpage content fetching with optimized performance
    """
    # Parse command line arguments
    parser = create_parser()
    args = parser.parse_args()

    # Ensure URL has a scheme
    args.url = ensure_scheme(args.url)

    # Validate URL
    if not is_valid_url(args.url):
        print(f"Error: Invalid URL '{args.url}'. Please provide a valid URL.", file=sys.stderr)
        sys.exit(1)

    # Setup output path if file output is selected
    output_dir = None
    output_path = None
    if args.output == 'file':
        output_path, output_dir = generate_output_path(
            args.filepath,
            args.url,
            args.mode,
            args.element
        )

    # Initialize driver
    driver = None

    try:
        # Configure Chrome Options with optimized settings
        options = create_driver_options(args)
        
        # Initialize WebDriver with optimized settings
        driver = webdriver.Remote(
            command_executor='http://selenium_service:4444/wd/hub',
            options=options
        )
        
        # Set appropriate timeouts
        driver.set_page_load_timeout(args.timeout_sec)
        driver.set_script_timeout(args.timeout_sec)
        
        try:
            # Load the webpage
            driver.get(args.url)
        except TimeoutException:
            print(f"Error: Connection timed out while trying to access {args.url}", file=sys.stderr)
            sys.exit(1)
        except WebDriverException as e:
            error_message = str(e).lower()
            if "err_name_not_resolved" in error_message:
                print(f"Error: Could not resolve the domain name for {args.url}. Please check if the URL is correct.", file=sys.stderr)
            elif "err_connection_refused" in error_message:
                print(f"Error: Connection was refused by {args.url}. The server might be down.", file=sys.stderr)
            elif "err_connection_timed_out" in error_message:
                print(f"Error: Connection timed out while trying to access {args.url}", file=sys.stderr)
            elif "err_ssl_protocol_error" in error_message:
                print(f"Error: SSL/TLS error occurred while trying to access {args.url}", file=sys.stderr)
            else:
                print(f"Error: Failed to access {args.url}. {str(e)}", file=sys.stderr)
            sys.exit(1)

        # Wait for page load completion
        try:
            WebDriverWait(driver, args.timeout_sec).until(
                lambda d: d.execute_script("return document.readyState") == "complete"
            )
        except TimeoutException:
            print(f"Error: Page load timed out for {args.url}", file=sys.stderr)
            sys.exit(1)

        # Find target element if specified
        element = None
        if args.element:
            try:
                element = driver.find_element(By.CSS_SELECTOR, args.element)
            except Exception as e:
                print(f"Error: Could not find element '{args.element}'. {e}", file=sys.stderr)
                sys.exit(1)

        # Handle PNG mode
        if args.mode == 'png':
            if args.output == 'stdout' and not args.print_text:
                print("Error: PNG mode cannot output to stdout", file=sys.stderr)
                sys.exit(1)
                
            # Capture screenshot
            if args.fullpage == 'false' and args.element:
                element.screenshot(output_path)
            else:
                if args.fullpage == 'true':
                    take_full_page_screenshot(driver, output_path)
                else:
                    driver.save_screenshot(output_path)
                
            # Validate captured image
            with Image.open(output_path) as img:
                extrema = img.convert("L").getextrema()
            if extrema == (0, 0) or extrema == (255, 255):
                os.remove(output_path)
                print(f"Error: Captured image was blank. Removed {output_path}", file=sys.stderr)
                sys.exit(1)
            else:
                print(f"Successfully saved screenshot to: {output_path}", file=sys.stderr)

            # Extract and handle text content if requested
            if args.print_text or args.save_metadata:
                text_content, metadata = extract_text(driver, element, args.url, args.keep_unknown)
                if args.print_text and text_content:
                    print("\n=== Content ===\n")
                    print(text_content)
                    print("\n=============\n")
                if args.save_metadata:
                    metadata_path = output_path.rsplit('.', 1)[0] + '_metadata.json'
                    with open(metadata_path, 'w', encoding='utf-8') as f:
                        json.dump(metadata, f, ensure_ascii=False, indent=2)
                    print(f"Saved metadata to: {metadata_path}", file=sys.stderr)
                
        # Handle Markdown mode
        elif args.mode == 'md':
            extracted, metadata = extract_text(driver, element, args.url, args.keep_unknown)
            if args.output == 'file':
                if extracted:
                    with open(output_path, 'w', encoding='utf-8') as f:
                        f.write(extracted)
                    print(f"Successfully saved content to: {output_path}", file=sys.stderr)
                    
                    if args.save_metadata:
                        metadata_path = output_path.rsplit('.', 1)[0] + '_metadata.json'
                        with open(metadata_path, 'w', encoding='utf-8') as f:
                            json.dump(metadata, f, ensure_ascii=False, indent=2)
                        print(f"Saved metadata to: {metadata_path}", file=sys.stderr)
                else:
                    print("Error: No content captured", file=sys.stderr)
                    sys.exit(1)
            else:  # stdout mode
                if not extracted:
                    print("Error: No content captured", file=sys.stderr)
                    sys.exit(1)
                print(extracted)
                if args.save_metadata:
                    print("\n=== Metadata ===\n")
                    print(json.dumps(metadata, ensure_ascii=False, indent=2))
                    print("\n=============\n")

    except Exception as e:
        print(f"Error: {str(e)}", file=sys.stderr)
        sys.exit(1)
    finally:
        if driver:
            driver.quit()

if __name__ == "__main__":
    main()
