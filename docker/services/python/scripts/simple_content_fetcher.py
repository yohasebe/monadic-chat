#!/usr/bin/env python3

import sys
import os
import re

def main():
    # Get the filepath from command line arguments
    filepath = sys.argv[1] if len(sys.argv) > 1 else None
    # Get the sizecap from command line arguments, defaulting to 10MB
    sizecap = int(sys.argv[2]) if len(sys.argv) > 2 else 10_000_000

    try:
        # Check if a filepath was provided
        if filepath is None:
            print("ERROR: No filepath provided.")
            sys.exit(1)

        # Check if the file exists and is readable
        if not os.path.isfile(filepath) or not os.access(filepath, os.R_OK):
            print(f"ERROR: File {filepath} does not exist or is not readable.")
            sys.exit(1)

        # Get the file size
        file_size = os.path.getsize(filepath)
        # Check if the file size exceeds the sizecap
        if file_size > sizecap:
            print(f"WARNING: File size exceeds sizecap ({file_size} bytes > {sizecap} bytes). "
                  f"Only the first {sizecap} bytes will be read.")

        # Open the file in read mode with UTF-8 encoding
        with open(filepath, "r", encoding="utf-8") as f:
            try:
                # Read a sample of the file to check content
                sample = f.read(1024)

                # Define what we consider as binary content
                # This regex looks for common control characters that shouldn't appear in text files
                # excluding normal whitespace characters (space, tab, CR, LF)
                binary_regex = r"[\x00-\x08\x0B\x0C\x0E-\x1A]"

                # Check if the sample contains binary content
                if re.search(binary_regex, sample):
                    print("ERROR: The file appears to be binary.")
                    sys.exit(1)

                # Seek back to the beginning of the file
                f.seek(0)

                # Read up to sizecap bytes from the file
                content = f.read(sizecap)

                # In Python, the content is already decoded as UTF-8 when reading
                # due to the encoding parameter in open()
                print(content)

            except UnicodeDecodeError as e:
                # Try to handle content as UTF-8 with invalid character replacement
                with open(filepath, "r", encoding="utf-8", errors="replace") as f:
                    content = f.read(sizecap)
                    print(content)

    except Exception as e:
        print(f"An error occurred: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    main()
