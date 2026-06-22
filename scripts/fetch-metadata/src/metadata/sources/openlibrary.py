import requests
from .base import Source, Metadata

class OpenLibrary(Source):
    BASE_URL = "https://openlibrary.org/api/books"

    def identify(self, log, abort, title=None, authors=None, identifiers=None):
        results = []
        query = {}
        if identifiers and "isbn" in identifiers:
            query["bibkeys"] = f"ISBN:{identifiers['isbn']}"
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
                if len(authors) <= 1 and item.get("by_statement"):
                    bs = item["by_statement"].rstrip(".")
                    for sep in ["/", "; ", ";", ", "]:
                        parts = [p.strip() for p in bs.split(sep) if p.strip()]
                        if len(parts) > len(authors):
                            authors = parts
                            break
                identifiers = {"isbn": key.replace("ISBN:", "")}
                # Handle notes as string or dict
                notes = item.get("notes")
                comments = notes.get("value") if isinstance(notes, dict) else notes
                # Combine title and subtitle
                full_title = item.get("title") or ""
                if item.get("subtitle"):
                    full_title = f"{full_title}: {item.get('subtitle')}"
                results.append(Metadata(
                    title=full_title,
                    authors=authors,
                    identifiers=identifiers,
                    publisher=publisher,
                    pubdate=item.get("publish_date"),
                    comments=comments
                ))
        except Exception as e:
            log.error(f"Open Library API error: {e}")

        return results