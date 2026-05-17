import requests
from io import BytesIO
from .base import create_log

def download_cover(log, identifiers, title=None, authors=None):
    log = log or create_log(BytesIO())
    if not identifiers:
        return None

    # Try Google Books cover
    isbn = identifiers.get("isbn")
    if isbn:
        url = f"https://books.google.com/books/content?isbn={isbn}&printsec=frontcover&img=1&zoom=1"
        try:
            resp = requests.get(url, timeout=10)
            resp.raise_for_status()
            if resp.headers.get("content-type", "").startswith("image"):
                return [resp.content]
        except Exception as e:
            log.error(f"Cover download error: {e}")

    return None