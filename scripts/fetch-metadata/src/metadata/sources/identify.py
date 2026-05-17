from .google import GoogleBooks
from .amazon import Amazon
from .openlibrary import OpenLibrary
from .base import Metadata

def format_author_name(author):
    """Convert author name to 'Last, First' format."""
    parts = author.strip().split()
    if len(parts) < 2:
        return author
    return f"{parts[-1]}, {' '.join(parts[:-1])}"

def identify(log, abort, title=None, authors=None, identifiers=None):
    results = []
    sources = [OpenLibrary(), GoogleBooks(), Amazon()]

    # Fetch results from all sources
    for source in sources:
        if abort.is_set():
            break
        try:
            source_results = source.identify(log, abort, title, authors, identifiers)
            results.extend(source_results)
        except Exception as e:
            log.error(f"Error in source {source.__class__.__name__}: {e}")

    # If no results, return empty list
    if not results:
        return []

    # Merge results into a single Metadata object
    merged = Metadata()
    google_result = None
    for result in results:
        # Title: Prefer Google Books, then exact match to input title, then longest
        if result.__class__.__name__ == "GoogleBooks" and result.title:
            google_result = result
            merged.title = result.title
        elif not merged.title or (title and result.title.lower() == title.lower()) or len(result.title or "") > len(merged.title or ""):
            merged.title = result.title
        # Authors: Use longest list and format names
        if not merged.authors or len(result.authors or []) > len(merged.authors):
            merged.authors = [format_author_name(author) for author in result.authors]
        # Identifiers: Merge all unique identifiers
        if result.identifiers:
            merged.identifiers.update(result.identifiers)
        # Publisher: Prefer non-empty
        if not merged.publisher and result.publisher:
            merged.publisher = result.publisher
        # Pubdate: Prefer non-empty
        if not merged.pubdate and result.pubdate:
            merged.pubdate = result.pubdate
        # Comments: Prefer longest non-empty description
        if not merged.comments or (result.comments and len(result.comments) > len(merged.comments or "")):
            merged.comments = result.comments

    # Fallback: Ensure Google Books title is used if available
    if google_result and google_result.title and google_result.title != merged.title:
        log.debug(f"Overriding title with Google Books: {google_result.title}")
        merged.title = google_result.title

    return [merged]