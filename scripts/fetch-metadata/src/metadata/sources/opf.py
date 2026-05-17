from xml.etree.ElementTree import Element, SubElement, tostring
from datetime import datetime

def metadata_to_opf(metadata):
    ns = {
        "dc": "http://purl.org/dc/elements/1.1/",
        "opf": "http://www.idpf.org/2007/opf"
    }

    package = Element("package", xmlns=ns["opf"], version="2.0", unique_identifier="BookId")
    metadata_elem = SubElement(package, "metadata", xmlns=ns["dc"])

    SubElement(metadata_elem, "dc:title").text = metadata.title
    for author in metadata.authors:
        SubElement(metadata_elem, "dc:creator", **{"opf:role": "aut"}).text = author
    for key, value in metadata.identifiers.items():
        SubElement(metadata_elem, "dc:identifier", id=key, **{"opf:scheme": key.upper()}).text = value
    if metadata.publisher:
        SubElement(metadata_elem, "dc:publisher").text = metadata.publisher
    if metadata.pubdate:
        SubElement(metadata_elem, "dc:date").text = metadata.pubdate
    if metadata.comments:
        SubElement(metadata_elem, "dc:description").text = metadata.comments

    return tostring(package, encoding="unicode", method="xml")