#!/usr/bin/env python3
"""Make a deterministic source archive; build products and biometric data are never included."""
import argparse
import gzip
from pathlib import Path
import tarfile

ROOT = Path(__file__).resolve().parents[1]
SKIP = {"build", "dist", ".git", "__pycache__", "homebrew-facegate"}

def package(destination):
    destination = Path(destination).resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open("wb") as output, gzip.GzipFile(fileobj=output, mode="wb", mtime=0, filename="") as compressed:
        with tarfile.open(fileobj=compressed, mode="w") as archive:
            for path in sorted(ROOT.rglob("*")):
                relative = path.relative_to(ROOT)
                if (any(p in SKIP for p in relative.parts) or path.suffix in {".onnx", ".pyc"}
                        or not path.is_file() or path.is_symlink() or path.resolve() == destination):
                    continue
                info = archive.gettarinfo(str(path), arcname=f"facegate-0.1.0/{relative.as_posix()}")
                info.uid = info.gid = 0; info.uname = info.gname = ""; info.mtime = 0
                info.mode = 0o755 if path.suffix in {".py", ".sh"} else 0o644
                with path.open("rb") as content: archive.addfile(info, content)
    return destination

if __name__ == "__main__":
    p = argparse.ArgumentParser(); p.add_argument("--output", type=Path, default=ROOT / "dist/facegate-0.1.0.tar.gz")
    print(package(p.parse_args().output))
