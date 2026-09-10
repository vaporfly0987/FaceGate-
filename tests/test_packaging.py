import importlib.util
from pathlib import Path
import tempfile
import unittest
import tarfile

ROOT = Path(__file__).resolve().parents[1]

def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / f"{name}.py")
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
    return mod

class PackagingTests(unittest.TestCase):
    def test_reproducible_archive_and_exclusions(self):
        pkg = module("package")
        with tempfile.TemporaryDirectory() as temp:
            a = pkg.package(Path(temp) / "a.tar.gz")
            b = pkg.package(Path(temp) / "b.tar.gz")
            self.assertEqual(a.read_bytes(), b.read_bytes())
            with tarfile.open(a) as tar:
                names = tar.getnames()
                self.assertIn("facegate-0.1.0/src/App.mm", names)
                self.assertFalse(any("/build/" in name or name.endswith(".onnx") for name in names))

    def test_local_and_remote_formula_and_injection(self):
        formula = module("make_formula")
        with tempfile.TemporaryDirectory() as temp:
            archive = Path(temp) / "source.tar.gz"; archive.write_bytes(b"source")
            local = formula.render(archive)
            self.assertIn(archive.as_uri(), local)
            self.assertNotIn("@SOURCE", local)
            remote = formula.render(archive, "example/facegate")
            self.assertIn("https://github.com/example/facegate/releases/download/v0.1.0/facegate-0.1.0.tar.gz", remote)
            with self.assertRaises(ValueError): formula.render(archive, 'bad/#{system("bad")}')
            self.assertTrue(formula.ruby_string("#{never_execute}").startswith("'"))

    def test_model_validation_rejects_wrong_bytes(self):
        downloader = module("download_models")
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "bad.onnx"; path.write_bytes(b"fake")
            self.assertFalse(downloader.verified(path, {"size": 4, "sha256": "0" * 64}))

if __name__ == "__main__": unittest.main()
