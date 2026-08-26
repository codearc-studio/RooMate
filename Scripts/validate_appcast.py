#!/usr/bin/env python3
"""Validate RooMate's Sparkle feed and, optionally, a release archive."""

from __future__ import annotations

import argparse
import base64
import os
import plistlib
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path
from urllib.parse import urlparse

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def fail(message: str) -> None:
    raise ValueError(message)


def child_text(item: ET.Element, name: str) -> str:
    value = item.findtext(f"{{{SPARKLE}}}{name}")
    if not value or not value.strip():
        fail(f"item is missing sparkle:{name}")
    return value.strip()


def load_items(feed_path: Path) -> list[dict[str, str]]:
    try:
        root = ET.parse(feed_path).getroot()
    except ET.ParseError as error:
        fail(f"invalid XML: {error}")

    items: list[dict[str, str]] = []
    seen_builds: set[int] = set()
    for element in root.findall("./channel/item"):
        enclosure = element.find("enclosure")
        if enclosure is None:
            fail("item is missing an enclosure")

        build_text = child_text(element, "version")
        try:
            build = int(build_text)
        except ValueError:
            fail(f"Sparkle build must be an integer: {build_text!r}")
        if build in seen_builds:
            fail(f"duplicate Sparkle build: {build}")
        seen_builds.add(build)

        minimum = child_text(element, "minimumSystemVersion")
        short_version = child_text(element, "shortVersionString")
        url = enclosure.get("url", "").strip()
        length = enclosure.get("length", "").strip()
        signature = enclosure.get(f"{{{SPARKLE}}}edSignature", "").strip()
        if not url.startswith("https://"):
            fail(f"enclosure must use HTTPS: {url!r}")
        if not length.isdigit() or int(length) <= 0:
            fail(f"invalid enclosure length for build {build}")
        if not signature:
            fail(f"missing EdDSA signature for build {build}")
        try:
            decoded_signature = base64.b64decode(signature, validate=True)
        except ValueError:
            fail(f"invalid base64 signature for build {build}")
        if len(decoded_signature) != 64:
            fail(f"invalid Ed25519 signature length for build {build}")

        items.append(
            {
                "build": str(build),
                "short": short_version,
                "minimum": minimum,
                "url": url,
                "length": length,
                "signature": signature,
            }
        )

    if not items:
        fail("feed contains no items")
    if [int(item["build"]) for item in items] != sorted(
        (int(item["build"]) for item in items), reverse=True
    ):
        fail("feed items must be ordered by descending Sparkle build")
    return items


def read_archive_info(archive: Path) -> dict[str, object]:
    with zipfile.ZipFile(archive) as zipped:
        matches = [
            name
            for name in zipped.namelist()
            if name.endswith(".app/Contents/Info.plist")
            and name.count(".app/") == 1
            and "__MACOSX/" not in name
        ]
        if len(matches) != 1:
            fail(f"expected one app Info.plist in archive, found {len(matches)}")
        return plistlib.loads(zipped.read(matches[0]))


def verify_signature(archive: Path, signature: str, public_key: str) -> None:
    raw_key = base64.b64decode(public_key, validate=True)
    if len(raw_key) != 32:
        fail("SUPublicEDKey must contain a 32-byte Ed25519 public key")

    openssl = os.environ.get("OPENSSL", "openssl")
    with tempfile.TemporaryDirectory(prefix="roomate-appcast-") as temp:
        temp_path = Path(temp)
        public_der = temp_path / "public.der"
        signature_file = temp_path / "signature.bin"
        public_der.write_bytes(bytes.fromhex("302a300506032b6570032100") + raw_key)
        signature_file.write_bytes(base64.b64decode(signature, validate=True))
        result = subprocess.run(
            [
                openssl,
                "pkeyutl",
                "-verify",
                "-pubin",
                "-inkey",
                str(public_der),
                "-keyform",
                "DER",
                "-rawin",
                "-in",
                str(archive),
                "-sigfile",
                str(signature_file),
            ],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            fail(f"archive signature verification failed: {result.stderr.strip()}")


def validate_archive(
    archive: Path, items: list[dict[str, str]], info_plist_path: Path
) -> None:
    archive_name = archive.name
    matching = [
        item
        for item in items
        if Path(urlparse(item["url"]).path).name == archive_name
    ]
    if len(matching) != 1:
        fail(f"expected exactly one feed item for {archive_name}, found {len(matching)}")
    item = matching[0]

    actual_length = archive.stat().st_size
    if actual_length != int(item["length"]):
        fail(f"archive length is {actual_length}; feed says {item['length']}")

    archive_info = read_archive_info(archive)
    archive_build = str(archive_info.get("CFBundleVersion", ""))
    archive_short = str(archive_info.get("CFBundleShortVersionString", ""))
    archive_minimum = str(archive_info.get("LSMinimumSystemVersion", ""))
    if archive_build != item["build"]:
        fail(f"archive build is {archive_build}; feed says {item['build']}")
    if archive_minimum != item["minimum"]:
        fail(
            f"archive minimum macOS is {archive_minimum}; feed says {item['minimum']}"
        )
    if archive_short != item["short"]:
        fail(
            f"archive short version is {archive_short}; feed says {item['short']}"
        )

    with info_plist_path.open("rb") as file:
        source_info = plistlib.load(file)
    public_key = str(source_info.get("SUPublicEDKey", ""))
    feed_url = str(source_info.get("SUFeedURL", ""))
    if not feed_url.startswith("https://"):
        fail("SUFeedURL must use HTTPS")
    verify_signature(archive, item["signature"], public_key)
    print(
        f"archive verified: short={archive_short}, build={archive_build}, "
        f"minimum macOS={archive_minimum}, signature=valid"
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("feed", type=Path)
    parser.add_argument("archive", type=Path, nargs="?")
    parser.add_argument(
        "--info-plist", type=Path, default=Path("RooMate/Info.plist")
    )
    args = parser.parse_args()
    try:
        items = load_items(args.feed)
        print(f"feed verified: valid XML, {len(items)} signed item(s)")
        if args.archive:
            validate_archive(args.archive, items, args.info_plist)
    except (OSError, ValueError, zipfile.BadZipFile, subprocess.SubprocessError) as error:
        print(f"appcast validation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
