#!/usr/bin/env python3
"""Generate a usable local formula, or a release formula for your real GitHub repository."""
import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def ruby_string(value):
    # Single-quoted Ruby strings disable #{...} interpolation.
    return "'" + str(value).replace("\\", "\\\\").replace("'", "\\'") + "'"

def render(archive, repository=None):
    archive = Path(archive).resolve()
    if repository is not None and not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*", repository):
        raise ValueError("repository must be OWNER/REPO")
    homepage = f"https://github.com/{repository}" if repository else "https://github.com"
    url = f"{homepage}/releases/download/v0.1.0/facegate-0.1.0.tar.gz" if repository else archive.as_uri()
    manifest = json.loads((ROOT / "models/manifest.json").read_text())
    resources = []
    for model in manifest["models"]:
        model_url = f"https://media.githubusercontent.com/media/{manifest['repository']}/{manifest['commit']}/{model['path']}"
        resources.append(f'''  resource {ruby_string(model['name'])} do
    url {ruby_string(model_url)}
    sha256 {ruby_string(model['sha256'])}
  end''')
    values = {
        "HOMEPAGE": ruby_string(homepage), "SOURCE_URL": ruby_string(url),
        "SOURCE_SHA": ruby_string(hashlib.sha256(archive.read_bytes()).hexdigest()),
        "MODEL_RESOURCES": "\n\n".join(resources),
    }
    text = (ROOT / "packaging/facegate.rb.in").read_text()
    for key, value in values.items(): text = text.replace(f"@{key}@", value)
    return text

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--repository", help="Actual GitHub OWNER/REPO, only after choosing your repository")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(render(args.archive, args.repository))
    print(args.output)
