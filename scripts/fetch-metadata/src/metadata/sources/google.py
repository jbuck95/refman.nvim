import requests
from .base import Source, Metadata
from isbnlib import canonical

class GoogleBooks(Source):
    BASE_URL = "https://www.googleapis.com/books/v1/volumes"

    def identify(self, log, abort, title=None, authors=None, identifiers=None):
        results = []
        query = []
        if title:
            query.append(f"intitle:{title}")
        if authors:
            query.append("from:" + "+".join(authors))
        if identifiers and "isbn" in identifiers:
            query.append(f"isbn:{canonical(identifiers['isbn'])}")

        if not query:
            return results

        params = {"q": "+".join(query)}
        try:
            resp = requests.get(self.BASE_URL, params=params, timeout=10)
            resp.raise_for_status()
            data = resp.json()

            for item in data.get("items", []):
                vol = item["volumeInfo"]
                if title and vol.get("title", "").lower() != title.lower():
                    continue
                identifiers = {}
                if "industryIdentifiers" in vol:
                    for ident in vol["industryIdentifiers"]:
                        if ident["type"].startswith("ISBN"):
                            identifiers["isbn"] = ident["identifier"]
                publisher = vol.get("publisher")
                log.debug(f"Google Books publisher: {publisher}")
                # Combine title and subtitle
                full_title = vol.get("title") or ""
                if vol.get("subtitle"):
                    full_title = f"{full_title}: {vol.get('subtitle')}"
                results.append(Metadata(
                    title=full_title,
                    authors=vol.get("authors", []),
                    identifiers=identifiers,
                    publisher=publisher,
                    pubdate=vol.get("publishedDate"),
                    comments=vol.get("description")
                ))
        except Exception as e:
            log.error(f"Google Books API error: {e}")

        return results