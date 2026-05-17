#!/usr/bin/env python3

import sys
from io import StringIO
from threading import Event
import logging
from datetime import datetime
from contextlib import suppress
import re

from metadata.sources.base import Source, create_log
from metadata.sources.identify import identify
from metadata.sources.covers import download_cover

# --- Start of Calibre's ISBN utility functions (simplified) ---

def check_digit_for_isbn10(isbn):
    check = sum((i+1)*int(isbn[i]) for i in range(9)) % 11
    return 'X' if check == 10 else str(check)

def check_digit_for_isbn13(isbn):
    check = 10 - sum((1 if i%2 ==0 else 3)*int(isbn[i]) for i in range(12)) % 10
    if check == 10:
        check = 0
    return str(check)

def check_isbn10(isbn):
    with suppress(Exception):
        return check_digit_for_isbn10(isbn) == isbn[9]
    return False

def check_isbn13(isbn):
    with suppress(Exception):
        return check_digit_for_isbn13(isbn) == isbn[12]
    return False

def check_isbn(isbn, simple_sanitize=False):
    if not isbn:
        return None
    if simple_sanitize:
        isbn = isbn.upper().replace('-', '').strip().replace(' ', '')
    else:
        isbn = re.sub(r'[^0-9X]', '', isbn.upper())
    il = len(isbn)
    if il not in (10, 13):
        return None
    all_same = re.match(r'(\d)\1{9,12}$', isbn)
    if all_same is not None:
        # print("DEBUG: ISBN consists of all same digits.")
        return None
    if il == 10:
        result = isbn if check_isbn10(isbn) else None
        # print(f"DEBUG: ISBN-10 check result: {result}")
        return result
    if il == 13:
        result = isbn if check_isbn13(isbn) else None
        # print(f"DEBUG: ISBN-13 check result: {result}")
        return result
    return None

def normalize_isbn(isbn):
    if not isbn:
        return isbn
    ans = check_isbn(isbn)
    if ans is None:
        return isbn
    if len(ans) == 10:
        ans = '978' + ans[:9]
        ans += check_digit_for_isbn13(ans)
    return ans

# --- End of Calibre's ISBN utility functions ---

def main():
    import argparse
    
    parser = argparse.ArgumentParser(description='Fetch book metadata from online sources')
    parser.add_argument('-t', '--title', help='Book title')
    parser.add_argument('-a', '--authors', help='Book authors (comma separated)')
    parser.add_argument('-i', '--isbn', help='Book ISBN') 
    parser.add_argument('-I', '--identifier', action='append', default=[],
                      help='Additional identifiers (e.g. asin:B0082BAJA0)')
    parser.add_argument('-c', '--cover', help='Save cover to this file')
    parser.add_argument('-o', '--opf', action='store_true',
                      help='Output metadata in OPF format')
    parser.add_argument('-v', '--verbose', action='store_true',
                      help='Enable verbose logging')
    
    args = parser.parse_args()

    # Setup logging
    log_buf = StringIO()
    log = create_log(log_buf)
    if args.verbose:
        logging.basicConfig(level=logging.DEBUG)

    # Parse authors
    authors = []
    if args.authors:
        authors = [a.strip() for a in args.authors.split(',')]

    # Parse identifiers 
    identifiers = {}
    if args.isbn:
        # Validate and normalize ISBN
        isbn_to_check = args.isbn.upper().replace('-', '').strip().replace(' ', '')
        if not check_isbn(isbn_to_check):
            print(f"Error: Invalid ISBN format: {args.isbn}", file=sys.stderr)
            return 1
        identifiers['isbn'] = normalize_isbn(args.isbn)

    for i in args.identifier:
        try:
            k, v = i.split(':', 1)
            identifiers[k] = v
        except ValueError:
            log.error(f'Invalid identifier format: {i}')

    # Fetch metadata
    abort = Event()
    results = identify(log, abort, title=args.title, authors=authors,
                      identifiers=identifiers)

    if not results:
        print("No results found", file=sys.stderr)
        return 1

    result = results[0]

    # Download cover if requested
    if args.cover:
        cover_data = download_cover(log, result.identifiers, 
                                  title=args.title,
                                  authors=authors)
        if cover_data:
            with open(args.cover, 'wb') as f:
                f.write(cover_data[-1])
            print(f"Cover saved to: {args.cover}")
        else:
            print("No cover found", file=sys.stderr)

    # Output results
    if args.opf:
        from metadata.opf import metadata_to_opf
        print(metadata_to_opf(result))
    else:
        print(f"Title: {result.title}")
        print(f"Authors: {', '.join(result.authors)}")
        print(f"Identifiers:")
        for k, v in result.identifiers.items():
            print(f"  {k}: {v}")
        if result.publisher:
            print(f"Publisher: {result.publisher}")
        if result.pubdate:
            print(f"Published: {result.pubdate}")
        if result.comments:
            print("\nDescription:")
            print(result.comments)

if __name__ == '__main__':
    sys.exit(main())
