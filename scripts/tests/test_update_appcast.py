"""
Unit tests for scripts/update-appcast.py.

Runs with plain `python3 -m unittest` (no third-party deps) so the release workflow can
gate the appcast generator without pulling pytest into the build job.

Covers:
  - parse_signature_file happy path (raw line, `sparkle:edSignature=""` attribute).
  - Malformed / rejected signatures (wrong length, wrong padding, multiple candidates).
  - main() end-to-end: valid args rewrite appcast to a single <item>; bad --zip-url /
    --zip-length values exit non-zero before touching the XML.
"""
from __future__ import annotations

import importlib.util
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

SCRIPT_PATH = Path(__file__).resolve().parents[1] / "update-appcast.py"


def _load_script_module():
    """Import the hyphenated script as a module so we can unit-test its helpers."""
    spec = importlib.util.spec_from_file_location("update_appcast", SCRIPT_PATH)
    assert spec is not None and spec.loader is not None, "could not locate update-appcast.py"
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


update_appcast = _load_script_module()

# A valid-shape Ed25519 base64 signature (88 chars, 2 trailing '='). The bytes are arbitrary
# - the script only checks the textual shape, not the actual Ed25519 validity.
VALID_SIG = "A" * 86 + "=="
EMPTY_APPCAST = """\
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>TinyAgenda</title>
  </channel>
</rss>
"""
POPULATED_APPCAST = """\
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>TinyAgenda</title>
    <item><title>Old</title></item>
    <item><title>Older</title></item>
  </channel>
</rss>
"""


class ParseSignatureTests(unittest.TestCase):
    def _write(self, tmp: Path, text: str) -> Path:
        p = tmp / "sig.txt"
        p.write_text(text, encoding="utf-8")
        return p

    def test_accepts_raw_base64_line(self):
        with TemporaryDirectory() as d:
            p = self._write(Path(d), f"{VALID_SIG}\n")
            self.assertEqual(update_appcast.parse_signature_file(p), VALID_SIG)

    def test_accepts_sparkle_attribute(self):
        with TemporaryDirectory() as d:
            p = self._write(Path(d), f'sparkle:edSignature="{VALID_SIG}" length="123"')
            self.assertEqual(update_appcast.parse_signature_file(p), VALID_SIG)

    def test_rejects_wrong_padding(self):
        # 85 chars + one '=' — wrong length for Ed25519.
        bad = "B" * 85 + "="
        with TemporaryDirectory() as d, self.assertRaises(SystemExit):
            update_appcast.parse_signature_file(self._write(Path(d), bad))

    def test_rejects_short_signature(self):
        with TemporaryDirectory() as d, self.assertRaises(SystemExit):
            update_appcast.parse_signature_file(self._write(Path(d), "tooshort"))

    def test_rejects_attribute_with_bad_shape(self):
        with TemporaryDirectory() as d, self.assertRaises(SystemExit):
            update_appcast.parse_signature_file(
                self._write(Path(d), 'sparkle:edSignature="not-base64!"')
            )

    def test_rejects_multiple_attribute_matches(self):
        text = f'sparkle:edSignature="{VALID_SIG}" sparkle:edSignature="{VALID_SIG}"'
        with TemporaryDirectory() as d, self.assertRaises(SystemExit):
            update_appcast.parse_signature_file(self._write(Path(d), text))

    def test_rejects_multiple_line_matches(self):
        other = "B" * 86 + "=="
        with TemporaryDirectory() as d, self.assertRaises(SystemExit):
            update_appcast.parse_signature_file(
                self._write(Path(d), f"{VALID_SIG}\n{other}\n")
            )


class MainCLITests(unittest.TestCase):
    def _run(self, appcast_text: str, *, overrides: dict | None = None):
        """Invoke `update-appcast.py` as a subprocess so we also exercise argparse.

        Temp directory is cleaned up via `addCleanup` (not a `with` block) so callers can
        still read the written appcast after this helper returns.
        """
        d = Path(tempfile.mkdtemp(prefix="update-appcast-test-"))
        self.addCleanup(shutil.rmtree, d, ignore_errors=True)
        appcast = d / "appcast.xml"
        appcast.write_text(appcast_text, encoding="utf-8")
        sig = d / "sig.txt"
        sig.write_text(VALID_SIG + "\n", encoding="utf-8")
        args: dict[str, str] = {
            "--appcast": str(appcast),
            "--short-version": "1.2.3",
            "--build-version": "1.2.3",
            "--min-os": "13.0",
            "--zip-url": "https://example.invalid/TinyAgenda-v1.2.3.zip",
            "--zip-length": "4096",
            "--signature-file": str(sig),
            "--pub-date": "Fri, 17 Apr 2026 12:00:00 GMT",
        }
        if overrides:
            args.update(overrides)
        cmd = [sys.executable, str(SCRIPT_PATH)]
        for k, v in args.items():
            cmd.extend([k, v])
        result = subprocess.run(cmd, capture_output=True, text=True)
        return result, appcast

    def test_happy_path_writes_single_item(self):
        result, appcast = self._run(POPULATED_APPCAST)
        self.assertEqual(
            result.returncode, 0, msg=f"stdout={result.stdout!r} stderr={result.stderr!r}"
        )
        written = appcast.read_text(encoding="utf-8")
        # Exactly one <item>: previous Old/Older entries dropped.
        self.assertEqual(written.count("<item>"), 1)
        self.assertIn("TinyAgenda 1.2.3", written)
        self.assertIn(VALID_SIG, written)
        self.assertIn("https://example.invalid/TinyAgenda-v1.2.3.zip", written)
        self.assertIn('length="4096"', written)
        self.assertNotIn("<title>Old</title>", written)

    def test_empty_channel_becomes_single_item(self):
        result, appcast = self._run(EMPTY_APPCAST)
        self.assertEqual(result.returncode, 0)
        written = appcast.read_text(encoding="utf-8")
        self.assertEqual(written.count("<item>"), 1)

    def test_http_zip_url_is_rejected(self):
        result, appcast = self._run(
            EMPTY_APPCAST,
            overrides={"--zip-url": "http://example.invalid/TinyAgenda-v1.2.3.zip"},
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("https URL", result.stderr)
        # Appcast must not have been rewritten on the error path.
        self.assertEqual(appcast.read_text(encoding="utf-8"), EMPTY_APPCAST)

    def test_non_integer_zip_length_is_rejected(self):
        result, appcast = self._run(EMPTY_APPCAST, overrides={"--zip-length": "not-a-number"})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("integer", result.stderr)
        self.assertEqual(appcast.read_text(encoding="utf-8"), EMPTY_APPCAST)

    def test_zero_zip_length_is_rejected(self):
        result, _ = self._run(EMPTY_APPCAST, overrides={"--zip-length": "0"})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("positive", result.stderr)


if __name__ == "__main__":
    unittest.main()
