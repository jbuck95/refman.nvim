import requests
from bs4 import BeautifulSoup
from .base import Source, Metadata
import time

class Amazon(Source):
    BASE_URL = "https://www.amazon.com/s"

    def identify(self, log, abort, title=None, authors=None, identifiers=None):
        results = []
        query = []
        if title:
            query.append(title)
        if authors:
            query.append(" ".join(authors))
        if identifiers and "isbn" in identifiers:
            query.append(f"isbn:{identifiers['isbn']}")

        if not query:
            return results

        headers = {
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/115.0",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.5",
        }
        params = {"k": " ".join(query), "i": "stripbooks"}

        for attempt in range(3):
            try:
                time.sleep(1)
                resp = requests.get(self.BASE_URL, params=params, headers=headers, timeout=10)
                resp.raise_for_status()
                soup = BeautifulSoup(resp.text, "lxml")

                for item in soup.select(".s-result-item"):
                    title_elem = item.select_one("h2 a span")
                    author_elem = item.select_one(".a-size-base:not(.a-color-price)")
                    # Look for publisher in details (often in product description or metadata)
                    publisher_elem = item.select_one(".a-size-base.a-color-secondary")
                    publisher = publisher_elem.text.strip() if publisher_elem else None
                    log.debug(f"Amazon publisher: {publisher}")  # Add debug log
                    if title_elem:
                        results.append(Metadata(
                            title=title_elem.text.strip(),
                            authors=[author_elem.text.strip()] if author_elem else [],
                            identifiers=identifiers or {},
                            publisher=publisher,
                            pubdate=None,
                            comments=None
                        ))
                break
            except Exception as e:
                log.error(f"Amazon attempt {attempt + 1} failed: {e}")
                if attempt == 2:
                    log.error("Amazon scraping failed after retries")
                    return results

        return results[:1]