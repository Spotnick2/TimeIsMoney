"""Offline checks for pinning, fetch rejection and lexical inventory boundaries."""
import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("reference", ROOT / "Tools/paperclips_reference.py")
reference = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reference)


def fixture():
    html = "".join(f'<script src="{name}?v3"></script>' for name in reference.SCRIPT_ORDER)
    blobs = {"index2.html": html.encode(), **{name: b"var x = 0;" for name in reference.SCRIPT_ORDER}}
    lock = {"files": [{"name": name, "url": "https://example.test/" + name,
                      "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
                     for name, data in blobs.items()]}
    return blobs, lock


class Response:
    def __init__(self, url, data):
        self.url, self.data, self.status, self.headers = url, data, 200, {}

    def read(self):
        return self.data

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


class ReferenceTests(unittest.TestCase):
    def test_lock_and_committed_evidence_match_owner_spec(self):
        lock = reference.load_lock()
        inventory = json.loads(reference.INVENTORY.read_text(encoding="utf-8"))
        self.assertEqual(inventory["source_sha256"], {f["name"]: f["sha256"] for f in lock["files"]})
        self.assertEqual(inventory["script_order"], reference.SCRIPT_ORDER)
        receipts = json.loads((ROOT / "docs/reference/retrieval-2026-10-02.json").read_text(encoding="utf-8"))
        self.assertEqual(len(receipts["files"]), 5)
        for file, receipt in zip(lock["files"], receipts["files"]):
            self.assertEqual((file["name"], file["url"], file["bytes"], file["sha256"]),
                             (receipt["name"], receipt["requested_url"], receipt["bytes"], receipt["sha256"]))
            self.assertEqual(receipt["http_status"], 200)
        projects = inventory["sources"]["projects.js"]
        self.assertEqual(len(projects["projects"]), 96)
        self.assertEqual(projects["project_registration_order"], [p["name"] for p in projects["projects"]])
        self.assertEqual(len(set(projects["project_registration_order"])), 96)
        for project in projects["projects"]:
            self.assertTrue({"id", "trigger", "cost", "effect", "uses", "flag"} <= project["fields"].keys())
        self.assertEqual(len(inventory["sources"]["combat.js"]["random_calls"]), 17)
        self.assertEqual(len(inventory["sources"]["main.js"]["random_calls"]), 23)

    def test_hash_mismatch_is_rejected(self):
        blobs, lock = fixture()
        blobs["main.js"] += b"\n"
        with self.assertRaisesRegex(ValueError, "main.js: expected"):
            reference.validate(blobs, lock)

    def test_matching_bytes_with_wrong_script_order_are_rejected(self):
        blobs, lock = fixture()
        blobs["index2.html"] = blobs["index2.html"].replace(b"combat.js?v3", b"combat.js?v2")
        file = lock["files"][0]
        file.update(bytes=len(blobs["index2.html"]), sha256=hashlib.sha256(blobs["index2.html"]).hexdigest())
        with self.assertRaisesRegex(ValueError, "order/query mismatch"):
            reference.validate(blobs, lock)

    def test_failed_fetch_leaves_existing_cache_untouched(self):
        blobs, lock = fixture()
        def open_response(request, timeout):
            name = request.full_url.rsplit("/", 1)[1]
            data = blobs[name] + (b"changed" if name == "main.js" else b"")
            return Response(request.full_url, data)
        with tempfile.TemporaryDirectory() as folder:
            cache = Path(folder)
            for name in blobs:
                (cache / name).write_bytes(b"previous")
            with patch.object(reference, "urlopen", side_effect=open_response):
                with self.assertRaisesRegex(ValueError, "main.js: expected"):
                    reference.fetch(cache, lock)
            self.assertTrue(all((cache / name).read_bytes() == b"previous" for name in blobs))
            self.assertFalse((cache / "retrieval.json").exists())

    def test_fetch_writes_exact_bytes_and_receipts(self):
        blobs, lock = fixture()
        def open_response(request, timeout):
            name = request.full_url.rsplit("/", 1)[1]
            return Response(request.full_url, blobs[name])
        with tempfile.TemporaryDirectory() as folder:
            cache = Path(folder) / "inputs"
            with patch.object(reference, "urlopen", side_effect=open_response):
                receipts = reference.fetch(cache, lock)
            self.assertEqual(reference.verify(cache, lock), blobs)
            self.assertEqual(len(receipts), 5)
            self.assertTrue((cache / "retrieval.json").is_file())

    def test_missing_cache_file_is_reported(self):
        _, lock = fixture()
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(FileNotFoundError):
                reference.verify(Path(folder), lock)

    def test_comments_strings_regex_and_closure_locals_are_not_sites(self):
        source = r"""
// Math.random(); setInterval(fake, 5);
var text = "Math.random(); /* setTimeout(fake, 1) */";
var pattern = /Math.random\(\)\{\}/;
var a = 1, b = [2, 3];
function outer(parameter) {
    var local = 0;
    function inner() { local++; parameter++; leaked++; Math.random(); }
    setTimeout(function() { b++; }, 50);
}
"""
        result = reference.analyse(source)
        self.assertEqual([d["name"] for d in result["top_level_declarations"]], ["text", "pattern", "a", "b"])
        self.assertEqual([d["name"] for d in result["implicit_global_write_candidates"]], ["leaked"])
        self.assertEqual(len(result["random_calls"]), 1)
        self.assertEqual(result["random_calls"][0]["scope"], "inner@8")
        self.assertEqual([(t["api"], t["delay_ms"]) for t in result["timers"]], [("setTimeout", "50")])

    def test_host_lookups_and_dynamic_keys_remain_distinct(self):
        result = reference.analyse("""
document.getElementById("fixed").value = 2;
document.getElementById("fixed").value;
document.getElementById("battle" + id).innerHTML = 3;
localStorage.setItem("saveGame", JSON.stringify(state));
""")
        lookups = result["host_lookups"]
        self.assertEqual(lookups[0]["lines"], [2, 3])
        self.assertFalse(lookups[0]["dynamic_first_argument"])
        self.assertTrue(lookups[1]["dynamic_first_argument"])
        self.assertEqual(result["host_member_sites"]["value"], {"write": [2], "read_or_reference": [3]})


if __name__ == "__main__":
    unittest.main()
