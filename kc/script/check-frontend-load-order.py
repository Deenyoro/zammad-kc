#!/usr/bin/env python3
"""Fail if KC legacy-UI CoffeeScript touches late-loaded classes at load time.

Zammad's legacy UI bundle (app/assets/javascripts/app/index.coffee) loads, in
order: lib/app_init, lib/mixins, config, models, controllers, views and only
then lib/app_post. Classes defined in lib/app_post (App.Event, App.Utils,
App.i18n, ...) do not exist yet while controllers are evaluated. Code that runs
at load time in a KC controller and uses one of them throws, and a single
uncaught error stops the whole app: it stays on "Loading..." for everyone
(2026-11-06, kc_article_type_display.coffee calling App.Event.bind).

"Load time" = top-level statements, statements inside top-level if/try/for
blocks, and class-body statements. Function bodies (after -> or =>) run later
and are fine.

Usage: kc/script/check-frontend-load-order.py [repo_root]
"""
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
app = root / "app/assets/javascripts/app"
index = app / "index.coffee"

# Directories that load after controllers, read from the manifest itself.
manifest = [l.strip() for l in index.read_text().splitlines() if l.strip().startswith("#= require")]
order = [l.split(None, 2)[-1] for l in manifest]
try:
    ctrl = order.index("./controllers")
except ValueError:
    sys.exit(f"cannot find ./controllers in {index}")
late_dirs = [app / p.lstrip("./") for p in order[ctrl + 1:] if p.startswith("./lib/")]

late = set()
define = re.compile(r"^\s*(?:class\s+App\.([A-Za-z_][\w]*)|App\.([A-Za-z_][\w]*)\s*=)")
for d in late_dirs:
    for f in d.rglob("*.coffee"):
        for line in f.read_text(errors="replace").splitlines():
            m = define.match(line)
            if m:
                late.add(m.group(1) or m.group(2))
# Defined early as well (e.g. reopened later) -> not late.
for d in (app / "lib/app_init", app / "lib/mixins", app / "models"):
    for f in d.rglob("*.coffee"):
        for line in f.read_text(errors="replace").splitlines():
            m = define.match(line)
            if m:
                late.discard(m.group(1) or m.group(2))
if not late:
    sys.exit("found no late-loaded classes; manifest layout changed, update this check")
late_ref = re.compile(r"\bApp\.(" + "|".join(sorted(map(re.escape, late))) + r")\b")

arrow = re.compile(r"(->|=>)")
kc_files = sorted((root / "kc/app/assets/javascripts").rglob("*.coffee"))
problems = []
for f in kc_files:
    lines = f.read_text(errors="replace").splitlines()
    stack = []  # (indent, is_function)
    in_block_comment = False
    for no, raw in enumerate(lines, 1):
        if raw.strip().startswith("###"):
            in_block_comment = not in_block_comment
            continue
        if in_block_comment or not raw.strip() or raw.strip().startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip())
        while stack and indent <= stack[-1][0]:
            stack.pop()
        in_function = any(fn for _, fn in stack)
        code = raw.split(" #", 1)[0]
        if not in_function:
            # Text after an arrow on the same line is a function body.
            load_part = arrow.split(code, 1)[0]
            m = late_ref.search(load_part)
            if m:
                problems.append(f"{f.relative_to(root)}:{no}: App.{m.group(1)} used at load time "
                                f"(defined in lib/app_post, after controllers): {raw.strip()}")
        # Does this line open a function body for the lines indented below it?
        opens_function = bool(re.search(r"(->|=>)\s*$", code.rstrip()))
        stack.append((indent, opens_function))

if problems:
    print("KC legacy UI load-order check FAILED:")
    print("\n".join("  " + p for p in problems))
    print("Move this code into a function that runs later (an App.Controller method, an "
          "App.Event handler, or an init that waits until the class exists).")
    sys.exit(1)
print(f"KC legacy UI load-order check OK: {len(kc_files)} files; late-loaded classes: "
      + ", ".join(sorted(late)))
