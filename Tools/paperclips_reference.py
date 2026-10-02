"""Fetch/verify the owner-pinned reference and inventory it without executing it.

Standard library only. Downloaded upstream bytes are local developer inputs, not
vendored addon code. The inventory is a lexical index, not an AST or parity proof.
"""
import argparse
import bisect
import hashlib
import json
import re
import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.request import Request, urlopen
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parent.parent
LOCK = ROOT / "docs/reference/paperclips.lock.json"
CACHE = ROOT / ".tmp-paperclips"
INVENTORY = ROOT / "docs/reference/inventory.json"
SCRIPT_ORDER = ["combat.js", "globals.js", "projects.js", "main.js"]


def load_lock():
    lock = json.loads(LOCK.read_text(encoding="utf-8"))
    if lock["script_order"] != SCRIPT_ORDER:
        raise ValueError("Unexpected script order in reference lock")
    expected_names = {"index2.html", *SCRIPT_ORDER}
    if {f["name"] for f in lock["files"]} != expected_names or len(lock["files"]) != 5:
        raise ValueError("Expected exactly the five pinned files")
    spec = (ROOT / "docs/plan/Time-Is-Money-Implementation-Spec.md").read_text(encoding="utf-8")
    for f in lock["files"]:
        expected_url = "https://www.decisionproblem.com/paperclips/" + f["name"] + (
            "?v3" if f["name"].endswith(".js") else "")
        if f["url"] != expected_url:
            raise ValueError(f"Unexpected official URL: {f['name']}")
        if not re.search(r"`" + re.escape(f["name"]) + r"`\s*\|\s*`" +
                         f["sha256"] + r"`", spec):
            raise ValueError(f"Lock disagrees with owner spec: {f['name']}")
    return lock


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.scripts = []
        self.events = []
        self.ids = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "script" and "src" in attrs:
            self.scripts.append(attrs["src"])
        if attrs.get("id"):
            self.ids.append(attrs["id"])
        for key, value in attrs.items():
            if key.startswith("on"):
                self.events.append({"line": self.getpos()[0], "element": attrs.get("id"),
                                    "event": key, "handler": value})


def validate(blobs, lock):
    for f in lock["files"]:
        data = blobs[f["name"]]
        actual = hashlib.sha256(data).hexdigest()
        if actual != f["sha256"] or len(data) != f["bytes"]:
            raise ValueError(f"{f['name']}: expected {f['sha256']} / {f['bytes']} bytes; "
                             f"observed {actual} / {len(data)} bytes")
    page = Page()
    page.feed(blobs["index2.html"].decode("utf-8"))
    gameplay = [s for s in page.scripts if s.split("?")[0] in SCRIPT_ORDER]
    if gameplay != [s + "?v3" for s in SCRIPT_ORDER]:
        raise ValueError(f"Gameplay script order/query mismatch: {gameplay}")
    return page


def verify(cache, lock):
    blobs = {f["name"]: (cache / f["name"]).read_bytes() for f in lock["files"]}
    validate(blobs, lock)
    return blobs


def fetch(cache, lock):
    # Validate ALL files before replacing any cached input. A failed fetch/hash
    # check leaves existing inputs intact and cannot silently select a new edition.
    blobs, receipts = {}, []
    for f in lock["files"]:
        request = Request(f["url"], headers={"Accept-Encoding": "identity",
                                            "User-Agent": "TimeIsMoney-reference/1"})
        with urlopen(request, timeout=30) as response:
            data = response.read()
            blobs[f["name"]] = data
            receipts.append({"name": f["name"], "requested_url": f["url"],
                             "final_url": response.url, "http_status": response.status,
                             "retrieved_at_utc": datetime.now(timezone.utc).isoformat(),
                             "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
                             "etag": response.headers.get("ETag"),
                             "last_modified": response.headers.get("Last-Modified")})
    validate(blobs, lock)
    cache.mkdir(parents=True, exist_ok=True)
    for name, data in blobs.items():
        (cache / name).write_bytes(data)
    (cache / "retrieval.json").write_text(
        json.dumps({"files": receipts}, indent=2) + "\n", encoding="utf-8")
    return receipts


# Strings/comments are tokens so comments and literal text cannot become RNG,
# host, state or timer sites. Regex literals are recognized in expression-start
# contexts; this deliberately small scanner is limited to the pinned scripts.
TOKEN = re.compile(
    r'(?P<space>\s+)|(?P<comment>//[^\n]*|/\*[\s\S]*?\*/)|'
    r'(?P<string>"(?:\\.|[^"\\])*"|\x27(?:\\.|[^\x27\\])*\x27)|'
    r'(?P<id>[A-Za-z_$][\w$]*)|(?P<number>\d+(?:\.\d*)?)|'
    r'(?P<op>===|!==|==|!=|<=|>=|\+\+|--|\+=|-=|\*=|/=|&&|\|\||.)')
REGEX_LITERAL = re.compile(r'/((?:\\.|\[(?:\\.|[^\]\\])*\]|[^/\n\\])+)/[a-z]*')


def tokens(text):
    out, pos = [], 0
    while pos < len(text):
        m = TOKEN.match(text, pos)
        kind, value = m.lastgroup, m.group()
        if value == "/" and (not out or out[-1][1] in
                             ("(", "=", ",", ":", "return", "[", "!", "&&", "||")):
            regex = REGEX_LITERAL.match(text, pos)
            if regex:
                out.append((pos, regex.group(), "regex"))
                pos = regex.end()
                continue
        if kind not in ("space", "comment"):
            out.append((pos, value, kind))
        pos = m.end()
    return out


def analyse(text):
    ts = tokens(text)
    starts = [0] + [m.end() for m in re.finditer("\n", text)]
    line = lambda i: bisect.bisect_right(starts, ts[i][0])
    pairs, stack = {}, []
    for i, (_, value, _) in enumerate(ts):
        if value in ("(", "[", "{"):
            stack.append(i)
        elif value in (")", "]", "}"):
            if not stack or ts[stack[-1]][1] != {")": "(", "]": "[", "}": "{"}[value]:
                raise ValueError(f"Unbalanced token at line {line(i)}")
            j = stack.pop()
            pairs[j] = i
    if stack:
        raise ValueError("Unclosed tokens")

    functions = []
    for i, (_, value, _) in enumerate(ts):
        if value != "function":
            continue
        j = i + 1
        name = None
        if ts[j][2] == "id":
            name = ts[j][1]
            j += 1
        end_params = pairs[j]
        body = end_params + 1
        if ts[j][1] != "(" or ts[body][1] != "{":
            raise ValueError(f"Unsupported function at line {line(i)}")
        label = name or (ts[i-2][1] if i >= 2 and ts[i-1][1] == ":" else "anonymous")
        params = {t[1] for t in ts[j+1:end_params] if t[2] == "id"}
        functions.append({"start": i, "body": body, "end": pairs[body],
                          "name": label, "line": line(i), "locals": params})

    def scopes(i):
        return [f for f in functions if f["body"] < i < f["end"]]

    def context(i):
        enclosing = scopes(i)
        return enclosing[-1]["name"] + "@" + str(enclosing[-1]["line"]) if enclosing else "top-level"

    declarations = []
    for i, (_, value, _) in enumerate(ts):
        if value not in ("var", "let", "const"):
            continue
        j = i + 1
        while j < len(ts):
            if ts[j][2] != "id":
                raise ValueError(f"Unsupported declaration at line {line(j)}")
            enclosing = scopes(i)
            if enclosing:
                enclosing[-1]["locals"].add(ts[j][1])
            else:
                declarations.append({"name": ts[j][1], "line": line(j)})
            j += 1
            while j < len(ts) and ts[j][1] not in (",", ";", "in", ")"):
                j = pairs[j] + 1 if j in pairs else j + 1
            if j == len(ts) or ts[j][1] != ",":
                break
            j += 1

    globals_ = {d["name"] for d in declarations}
    writes, random, timers, host, lookups, member_sites = {}, [], [], [], [], {}
    project_defs, project_order = [], []
    for i, (_, value, kind) in enumerate(ts):
        if kind != "id":
            continue
        if i + 1 < len(ts) and ts[i+1][1] in ("=", "+=", "-=", "*=", "/=", "++", "--"):
            if i == 0 or ts[i-1][1] != ".":
                local = set().union(*(s["locals"] for s in scopes(i)))
                if value not in local and value not in globals_:
                    writes.setdefault(value, []).append(line(i))
        if [t[1] for t in ts[i:i+4]] == ["Math", ".", "random", "("]:
            random.append({"line": line(i), "scope": context(i)})
        if value in ("setInterval", "setTimeout", "clearInterval", "clearTimeout") and ts[i+1][1] == "(":
            j, end, args = i+2, pairs[i+1], []
            start = j
            while j < end:
                if ts[j][1] == ",":
                    args.append(ts[start:j])
                    start = j+1
                j = pairs[j]+1 if j in pairs else j+1
            args.append(ts[start:end])
            callback = args[0][0][1] if args[0] else None
            delay = "".join(t[1] for t in args[1]) if len(args) > 1 else None
            timers.append({"line": line(i), "scope": context(i), "api": value,
                           "callback_or_handle": callback, "delay_ms": delay})
        if value in ("document", "localStorage", "location", "window", "console") and ts[i+1][1] == ".":
            method = ts[i+2][1]
            host.append({"line": line(i), "api": value + "." + method})
            if method in ("getElementById", "getItem", "setItem", "removeItem", "createElement") and ts[i+3][1] == "(":
                end = pairs[i+3]
                arg = ts[i+4:end]
                first = arg[0] if arg else None
                lookups.append({"line": line(i), "api": value + "." + method,
                                "first_literal": first[1][1:-1] if first and first[2] == "string" else None,
                                "dynamic_first_argument": bool(arg and len(arg) > 1 and arg[1][1] != ",")})
        if i > 0 and ts[i-1][1] == "." and value in {
                "value", "checked", "selectedIndex", "options", "innerHTML", "textContent",
                "display", "visibility", "opacity", "backgroundColor", "color", "disabled",
                "childNodes", "firstChild", "parentNode", "appendChild", "removeChild",
                "insertBefore", "setAttribute", "getContext", "fillRect", "fillStyle",
                "width", "height", "onclick", "addEventListener", "src", "play"}:
            following = ts[i+1][1] if i+1 < len(ts) else None
            access = ("write" if following in ("=", "+=", "-=", "++", "--")
                      else "call" if following == "(" else "read_or_reference")
            member_sites.setdefault(value, {}).setdefault(access, []).append(line(i))
        if re.fullmatch(r"project\d+[a-z]?", value) and i > 0 and ts[i-1][1] == "var" and ts[i+1][1] == "=":
            body = i+2
            if ts[body][1] != "{":
                continue
            fields, j = {}, body+1
            while j < pairs[body]:
                if j+2 < len(ts) and ts[j+1][1] == ":":
                    field, val = ts[j][1], ts[j+2]
                    fields[field] = {"line": line(j)}
                    if field in ("id", "uses", "flag"):
                        fields[field]["initial"] = val[1].strip("\"'")
                    j += 2
                j = pairs[j]+1 if j in pairs else j+1
            project_defs.append({"name": value, "line": line(i), "fields": fields})
        if [t[1] for t in ts[i:i+4]] == ["projects", ".", "push", "("]:
            project_order.append(ts[i+4][1])

    properties = sorted({ts[i+1][1] for i, t in enumerate(ts[:-1])
                         if t[1] == "." and ts[i+1][2] == "id"})
    def group_sites(records, keys):
        groups = {}
        for record in records:
            key = tuple(record[k] for k in keys)
            groups.setdefault(key, []).append(record["line"])
        return [dict(zip(keys, key), lines=sorted(set(lines))) for key, lines in groups.items()]

    return {"top_level_declarations": declarations,
            "implicit_global_write_candidates": [{"name": k, "lines": sorted(set(v))}
                                                  for k, v in sorted(writes.items())],
            "functions": [{"name": f["name"], "line": f["line"], "end_line": line(f["end"])}
                          for f in functions],
            "random_calls": random, "timers": timers,
            "host_calls": group_sites(host, ("api",)),
            "host_lookups": group_sites(lookups, ("api", "first_literal", "dynamic_first_argument")),
            "host_member_sites": member_sites,
            "member_names": properties,
            "projects": project_defs, "project_registration_order": project_order}


def inventory(blobs, lock):
    page = validate(blobs, lock)
    sources = {name: analyse(blobs[name].decode("utf-8")) for name in SCRIPT_ORDER}
    projects = sources["projects.js"]
    if len(projects["projects"]) != 96 or projects["project_registration_order"] != [
            p["name"] for p in projects["projects"]]:
        raise ValueError("Expected 96 definitions registered in declaration order")
    return {"schema": 1, "source_sha256": {f["name"]: f["sha256"] for f in lock["files"]},
            "script_order": SCRIPT_ORDER, "html_events": page.events,
            "html_ids": page.ids, "sources": sources}


def render(value):
    # One record per line keeps the large identifier index readable and compact.
    if isinstance(value, dict):
        return "{\n" + ",\n".join(json.dumps(k) + ": " + render(v) for k, v in value.items()) + "\n}"
    if isinstance(value, list):
        return "[\n" + ",\n".join(json.dumps(v, ensure_ascii=False) for v in value) + "\n]"
    return json.dumps(value, ensure_ascii=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("fetch", "verify", "inventory"))
    parser.add_argument("--cache", type=Path, default=CACHE)
    parser.add_argument("--output", type=Path, default=INVENTORY)
    parser.add_argument("--check", action="store_true", help="Compare inventory without writing it")
    args = parser.parse_args()
    if args.check and args.mode != "inventory":
        parser.error("--check is only valid for inventory")
    lock = load_lock()
    if args.mode == "fetch":
        receipts = fetch(args.cache, lock)
        for r in receipts:
            print(f"{r['name']}: {r['sha256']} / {r['bytes']} bytes")
    else:
        blobs = verify(args.cache, lock)
        if args.mode == "inventory":
            text = render(inventory(blobs, lock)) + "\n"
            if args.check:
                if args.output.read_text(encoding="utf-8") != text:
                    raise ValueError("Recorded inventory differs from verified source")
            else:
                args.output.parent.mkdir(parents=True, exist_ok=True)
                args.output.write_text(text, encoding="utf-8")
            print("Static inventory matches verified inputs" if args.check else "Static inventory generated")
        print("All five hashes/byte sizes and ?v3 script order verified")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError) as exc:
        print(f"reference: {exc}", file=sys.stderr)
        sys.exit(1)
