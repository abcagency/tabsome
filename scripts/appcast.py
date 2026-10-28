"""Adds one release to Sparkle's update feed, docs/appcast.xml (PLAN.md §7 Phase 7c).

  python3 -I scripts/appcast.py <appcast.xml> <version> <build> <dmg url> <length> <ed signature> <notes.md>

Newest first. Re-adding a build replaces its entry. The feed is signed afterwards with
sign_update, which embeds its signature in the file (the app requires a signed feed), so any old
signature is dropped here first.
"""
import email.utils
import re
import sys
import xml.etree.ElementTree as ET

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)
FEED_URL = "https://abcagency.github.io/tabsome/appcast.xml"
MIN_SYSTEM = "26.0"


def s(tag):
    return f"{{{SPARKLE}}}{tag}"


def main(path, version, build, url, length, signature, notes_path):
    try:
        text = open(path, encoding="utf-8").read()
        # sign_update's embedded signature is an XML comment; it's redone after this edit.
        text = re.sub(r"<!--\s*sparkle-signatures:.*?-->\s*", "", text, flags=re.S)
        root = ET.fromstring(text)
    except FileNotFoundError:
        root = ET.Element("rss", {"version": "2.0"})
        channel = ET.SubElement(root, "channel")
        ET.SubElement(channel, "title").text = "Tabsome"
        ET.SubElement(channel, "link").text = FEED_URL
        ET.SubElement(channel, "description").text = "Tabsome updates"
        ET.SubElement(channel, "language").text = "en"
    channel = root.find("channel")
    for old in channel.findall("item"):
        if old.findtext(s("version")) == build:
            channel.remove(old)

    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"Version {version}"
    ET.SubElement(item, "pubDate").text = email.utils.formatdate(usegmt=True)
    ET.SubElement(item, s("version")).text = build
    ET.SubElement(item, s("shortVersionString")).text = version
    ET.SubElement(item, s("minimumSystemVersion")).text = MIN_SYSTEM
    notes = ET.SubElement(item, "description", {s("format"): "markdown"})
    notes.text = open(notes_path, encoding="utf-8").read().strip()
    ET.SubElement(item, "enclosure", {
        "url": url,
        "length": length,
        "type": "application/octet-stream",
        s("edSignature"): signature,
    })
    items = channel.findall("item")
    position = list(channel).index(items[0]) if items else len(channel)
    channel.insert(position, item)

    ET.indent(root, space="  ")
    out = ET.tostring(root, encoding="unicode", xml_declaration=False)
    with open(path, "w", encoding="utf-8") as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n' + out + "\n")


if __name__ == "__main__":
    if len(sys.argv) != 8:
        sys.exit(__doc__)
    main(*sys.argv[1:])
