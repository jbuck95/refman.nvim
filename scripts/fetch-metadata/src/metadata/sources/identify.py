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
    all_results = []
    sources = [("GoogleBooks", GoogleBooks()), ("OpenLibrary", OpenLibrary()), ("Amazon", Amazon())]

    for src_name, source in sources:
        if abort.is_set():
            break
        try:
            source_results = source.identify(log, abort, title, authors, identifiers)
            for r in source_results:
                all_results.append((src_name, r))
        except Exception as e:
            log.error(f"Error in source {src_name}: {e}")

    if not all_results:
        return []

    merged = Metadata()

    priority = {"GoogleBooks": 1, "OpenLibrary": 2, "Amazon": 3}
    sorted_results = sorted(all_results, key=lambda x: priority.get(x[0], 99))

    for src_name, result in sorted_results:
        if (not merged.title or merged.title == "Unknown") and result.title and result.title != "Unknown":
            merged.title = result.title
        if not merged.authors and result.authors:
            merged.authors = [format_author_name(a) for a in result.authors]
        if result.identifiers:
            merged.identifiers.update(result.identifiers)
        if not merged.publisher and result.publisher:
            merged.publisher = result.publisher
        if not merged.pubdate and result.pubdate:
            merged.pubdate = result.pubdate
        if not merged.comments and result.comments:
            merged.comments = result.comments

    return [merged]