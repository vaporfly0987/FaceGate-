#!/usr/bin/env python3
"""Download only pinned model bytes; never accept a Git LFS pointer as a model."""
import argparse
import hashlib
import json
from pathlib import Path
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]

def verified(path, model):
    return (path.is_file() and path.stat().st_size == model["size"]
            and hashlib.sha256(path.read_bytes()).hexdigest() == model["sha256"])

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--destination", type=Path, default=ROOT / "models")
    args = parser.parse_args()
    manifest = json.loads((ROOT / "models/manifest.json").read_text())
    args.destination.mkdir(parents=True, exist_ok=True)
    for model in manifest["models"]:
        destination = args.destination / model["name"]
        if verified(destination, model):
            print(f"Verified {model['name']}")
            continue
        url = (f"https://media.githubusercontent.com/media/{manifest['repository']}/"
               f"{manifest['commit']}/{model['path']}")
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(dir=args.destination, delete=False) as out:
                temporary = Path(out.name)
                with urllib.request.urlopen(url, timeout=45) as response:
                    total = 0
                    while chunk := response.read(1024 * 1024):
                        total += len(chunk)
                        if total > model["size"]:
                            raise ValueError("Model response exceeded pinned size")
                        out.write(chunk)
            if not verified(temporary, model):
                raise ValueError(f"Checksum/size mismatch: {model['name']}")
            temporary.replace(destination)
            print(f"Downloaded and verified {model['name']}")
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)

if __name__ == "__main__":
    main()
