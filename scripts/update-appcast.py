#!/usr/bin/env python3
"""
Replace Sparkle appcast.xml with exactly one <item>: the latest release only.

(Sparkle supports multiple items, but this feed intentionally carries a single entry so
the raw GitHub URL always reflects one current version.)

Reads EdDSA signature from sign_update output (raw base64 or sparkle:edSignature="...").
"""
from __future__ import annotations

import argparse
import re
import sys
import xml.etree.ElementTree as ET
from email.utils import formatdate
from pathlib import Path

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"

# `sign_update` emits Ed25519 signatures: 64 raw bytes → exactly 88 base64 chars (2 trailing `=`).
# Pin that shape so a truncated or corrupted signature file fails loudly instead of silently
# writing an attacker-controlled blob into the appcast.
_ED25519_SIG_RE = re.compile(r"[A-Za-z0-9+/]{86}==")


def parse_signature_file(path: Path) -> str:
    raw = path.read_text(encoding="utf-8", errors="replace")

    attr_matches = re.findall(r'sparkle:edSignature="([^"]*)"', raw)
    if len(attr_matches) > 1:
        raise SystemExit(
            f"error: multiple sparkle:edSignature values in {path}; refusing to guess"
        )
    if attr_matches:
        sig = attr_matches[0].strip()
        if not _ED25519_SIG_RE.fullmatch(sig):
            raise SystemExit(f"error: sparkle:edSignature in {path} is not a valid Ed25519 base64 signature")
        return sig

    line_matches = [
        line.strip() for line in raw.splitlines() if _ED25519_SIG_RE.fullmatch(line.strip())
    ]
    if len(line_matches) > 1:
        raise SystemExit(f"error: multiple signature-shaped lines in {path}; refusing to guess")
    if line_matches:
        return line_matches[0]

    raise SystemExit(f"error: could not parse EdDSA signature from {path}")


def main() -> None:
    p = argparse.ArgumentParser(description="Update Sparkle appcast.xml with a release item.")
    p.add_argument("--appcast", type=Path, required=True)
    p.add_argument("--short-version", required=True)
    p.add_argument("--build-version", required=True)
    p.add_argument("--min-os", default="13.0")
    p.add_argument("--zip-url", required=True)
    p.add_argument("--zip-length", required=True)
    p.add_argument("--signature-file", type=Path, required=True)
    p.add_argument(
        "--pub-date",
        help="RFC 2822 date (default: now UTC)",
    )
    args = p.parse_args()

    try:
        zip_length = int(args.zip_length)
    except ValueError:
        sys.exit(f"error: --zip-length must be an integer, got {args.zip_length!r}")
    if zip_length <= 0:
        sys.exit(f"error: --zip-length must be positive, got {zip_length}")

    if not args.zip_url.startswith("https://"):
        sys.exit(f"error: --zip-url must be an https URL, got {args.zip_url!r}")

    sig = parse_signature_file(args.signature_file)

    pub = args.pub_date or formatdate(usegmt=True)

    ET.register_namespace("sparkle", SPARKLE_NS)

    tree = ET.parse(args.appcast)
    root = tree.getroot()
    channel = root.find("channel")
    if channel is None:
        sys.exit("error: no <channel> in appcast")

    # Only one <item>: drop every previous release entry, then add this build.
    for old in list(channel.findall("item")):
        channel.remove(old)

    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"TinyAgenda {args.short_version}"
    ET.SubElement(item, "pubDate").text = pub

    sv = ET.SubElement(item, f"{{{SPARKLE_NS}}}version")
    sv.text = args.build_version

    svs = ET.SubElement(item, f"{{{SPARKLE_NS}}}shortVersionString")
    svs.text = args.short_version

    minos = ET.SubElement(item, f"{{{SPARKLE_NS}}}minimumSystemVersion")
    minos.text = args.min_os

    enclosure = ET.SubElement(item, "enclosure")
    enclosure.set("url", args.zip_url)
    enclosure.set("length", str(zip_length))
    enclosure.set("type", "application/octet-stream")
    enclosure.set(f"{{{SPARKLE_NS}}}edSignature", sig)

    channel.append(item)

    try:
        ET.indent(tree, space="  ")
    except AttributeError:
        pass

    tree.write(
        args.appcast,
        encoding="utf-8",
        xml_declaration=True,
        default_namespace=None,
    )
    print(f"Updated {args.appcast} with version {args.short_version} ({args.build_version}).")


if __name__ == "__main__":
    main()
