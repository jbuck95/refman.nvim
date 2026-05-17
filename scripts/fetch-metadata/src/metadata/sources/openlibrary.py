import requests
from .base import Source, Metadata
from isbnlib import canonical

class OpenLibrary(Source):
    BASE_URL = "https://openlibrary.org/api/books"

    def identify(self, log, abort, title=None, authors=None, identifiers=None):
        results = []
        query = {}
        if identifiers and "isbn" in identifiers:
            query["bibkeys"] = f"ISBN:{canonical(identifiers['isbn'])}"
        else:
            return results

        query["format"] = "json"
        query["jscmd"] = "data"
        try:
            resp = requests.get(self.BASE_URL, params=query, timeout=10)
            resp.raise_for_status()
            data = resp.json()

            for key, item in data.items():
                publisher = item.get("publishers", [{}])[0].get("name") if item.get("publishers") else None
                log.debug(f"Open Library publisher: {publisher}")
                authors = [a["name"] for a in item.get("authors", [])] if item.get("authors") else []
                identifiers = {"isbn": key.replace("ISBN:", "")}
                # Handle notes as string or dict
                notes = item.get("notes")
                comments = notes.get("value") if isinstance(notes, dict) else notes
                results.append(Metadata(
                    title=item.get("title"),
                    authors=authors,
                    identifiers=identifiers,
                    publisher=publisher,
                    pubdate=item.get("publish_date"),
                    comments=comments
                ))
        except Exception as e:
            log.error(f"Open Library API error: {e}")

        return results