from io import StringIO  # Use StringIO, not BytesIO
import logging

class Source:
    def __init__(self):
        self.logger = logging.getLogger(self.__class__.__name__)

def create_log(log_buf=None):
    log = logging.getLogger("fetch_metadata")
    log_buf = log_buf or StringIO()  # Use StringIO
    handler = logging.StreamHandler(log_buf)
    formatter = logging.Formatter("%(levelname)s: %(message)s")
    handler.setFormatter(formatter)
    log.addHandler(handler)
    log.setLevel(logging.INFO)
    return log

class Metadata:
    def __init__(self, title=None, authors=None, identifiers=None, publisher=None,
                 pubdate=None, comments=None):
        self.title = title or "Unknown"
        self.authors = authors or []
        self.identifiers = identifiers or {}
        self.publisher = publisher
        self.pubdate = pubdate
        self.comments = comments