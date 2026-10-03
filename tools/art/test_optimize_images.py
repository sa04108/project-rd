#!/usr/bin/env python3
"""압축 도구의 읽기 전용 기본값·알파·복구·품질 하한 계약을 확인한다."""

import hashlib
import importlib.util
import io
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest import mock

from PIL import Image, PngImagePlugin, features


SPEC = importlib.util.spec_from_file_location("optimize_images", Path(__file__).with_name("optimize_images.py"))
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class OptimizationContract(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.root = self.base / "repo"
        self.root.mkdir()
        self.path = self.root / "assets" / "source.png"
        self.path.parent.mkdir()
        image = Image.new("RGBA", (32, 32))
        image.putdata([(x * 8, y * 8, (x + y) * 4, (x + y * 32) % 256) for y in range(32) for x in range(32)])
        image.save(self.path, compress_level=0)
        self.original = self.path.read_bytes()
        self.image = MODULE.load_source(self.original)

    def args(self, *extra):
        return MODULE.parser().parse_args([str(self.path), *map(str, extra)])

    def run_tool(self, *extra):
        return MODULE.run(self.args(*extra), self.root)

    def test_default_is_read_only_and_lossless(self):
        tree = sorted(self.base.rglob("*"))
        report, status = self.run_tool()
        self.assertEqual(status, 0)
        self.assertEqual(report["mode"], "dry-run")
        self.assertEqual(self.path.read_bytes(), self.original)
        self.assertEqual(sorted(self.base.rglob("*")), tree)
        candidate = report["files"][0]["candidates"][0]
        self.assertEqual(candidate["method"], "png-lossless")
        self.assertTrue(candidate["metrics"]["rgba_exact"])
        self.assertTrue(candidate["metrics"]["alpha_exact"])
        self.assertEqual(candidate["after"]["png_color_type"], 6)
        self.assertGreater(candidate["saved_bytes"], 0)

    def test_apply_creates_verified_external_backup_and_receipt(self):
        self.path.chmod(0o640)
        report, status = self.run_tool("--apply", "--backup-dir", self.base / "backups")
        self.assertEqual(status, 0)
        entry = report["files"][0]
        self.assertEqual(entry["status"], "applied")
        self.assertEqual(Path(entry["backup"]).read_bytes(), self.original)
        self.assertFalse(Path(entry["backup"]).is_relative_to(self.root))
        journal = json.loads(Path(entry["receipt"]).read_text())
        self.assertEqual(journal["status"], "applied")
        self.assertEqual(journal["before"]["sha256"], hashlib.sha256(self.original).hexdigest())
        self.assertEqual(journal["candidate"]["after"]["sha256"], hashlib.sha256(self.path.read_bytes()).hexdigest())
        self.assertEqual(MODULE.decode(self.path.read_bytes()).tobytes(), self.image.tobytes())
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o640)
        self.assertFalse(list(self.path.parent.glob("*.tmp")))

    def test_apply_requires_external_backup(self):
        for extra in (("--apply",), ("--apply", "--backup-dir", str(self.root / "backup"))):
            with self.subTest(extra=extra), self.assertRaises(ValueError):
                self.run_tool(*extra)
        self.assertEqual(self.path.read_bytes(), self.original)

    def test_symlink_file_and_parent_are_skipped(self):
        file_link = self.root / "alias.png"
        file_link.symlink_to(self.path)
        parent_link = self.root / "alias-folder"
        parent_link.symlink_to(self.path.parent, target_is_directory=True)
        args = MODULE.parser().parse_args([str(file_link), str(parent_link / self.path.name)])
        report, status = MODULE.run(args, self.root)
        self.assertEqual(status, 0)
        self.assertEqual([entry["status"] for entry in report["files"]], ["skipped", "skipped"])
        self.assertEqual(self.path.read_bytes(), self.original)

    def test_symlink_backup_is_rejected(self):
        destination = self.base / "actual-backup"
        destination.mkdir()
        link = self.base / "backup-link"
        link.symlink_to(destination, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "symlink"):
            self.run_tool("--apply", "--backup-dir", link)

    def test_explicit_file_selection_only(self):
        args = MODULE.parser().parse_args([str(self.path.parent)])
        report, status = MODULE.run(args, self.root)
        self.assertEqual(status, 1)
        self.assertEqual(report["files"][0]["status"], "error")

    def test_parent_traversal_is_rejected(self):
        with self.assertRaises(ValueError):
            MODULE.no_symlinks(self.path.parent / ".." / "assets" / "source.png")

    def test_duplicate_path_is_skipped(self):
        report, status = MODULE.run(MODULE.parser().parse_args([str(self.path), str(self.path)]), self.root)
        self.assertEqual(status, 0)
        self.assertEqual(report["files"][1]["status"], "skipped")

    def test_source_outside_repository_is_rejected(self):
        outside = self.base / "outside.png"
        outside.write_bytes(self.original)
        report, status = MODULE.run(MODULE.parser().parse_args([str(outside)]), self.root)
        self.assertEqual(status, 1)
        self.assertIn("inside repository", report["files"][0]["error"])

    def test_all_alpha_values_survive_rgb_palette_reduction(self):
        encoded, candidate = MODULE.evaluate(self.original, self.image, "png-rgb", self.args("--colors", "32"))
        decoded = MODULE.decode(encoded)
        self.assertEqual(decoded.mode, "RGBA")
        self.assertEqual(candidate["after"]["png_color_type"], 6)
        self.assertEqual(decoded.getchannel("A").tobytes(), self.image.getchannel("A").tobytes())
        self.assertEqual(set(decoded.getchannel("A").tobytes()), set(range(256)))
        self.assertFalse(candidate["metrics"]["rgba_exact"])

    def test_hidden_cleanup_preserves_partial_alpha_rgb_exactly(self):
        encoded, candidate = MODULE.evaluate(self.original, self.image, "png-clean-alpha0", self.args())
        decoded = MODULE.decode(encoded)
        for y in range(self.image.height):
            for x in range(self.image.width):
                before, after = self.image.getpixel((x, y)), decoded.getpixel((x, y))
                self.assertEqual(after, before if before[3] else (0, 0, 0, 0))
        self.assertTrue(candidate["metrics"]["visible_rgb_exact"])
        self.assertTrue(candidate["metrics"]["alpha_exact"])
        self.assertFalse(candidate["metrics"]["rgba_exact"])

    def test_runtime_cannot_apply_lossy_or_hidden_rgb_changes(self):
        for method in ("png-rgb", "png-clean-alpha0"):
            with self.subTest(method=method), self.assertRaisesRegex(ValueError, "runtime"):
                self.run_tool("--method", method, "--apply", "--backup-dir", self.base / "backup", "--allow-lossy", "--allow-transparent-rgb-cleanup")

    def test_lossy_and_cleanup_each_require_explicit_opt_in(self):
        for method in ("png-rgb", "png-clean-alpha0"):
            with self.subTest(method=method), self.assertRaises(ValueError):
                self.run_tool("--method", method, "--role", "source", "--apply", "--backup-dir", self.base / "backup")

    def test_quality_failure_keeps_original_even_when_large(self):
        report, status = self.run_tool("--method", "png-rgb", "--role", "source", "--apply", "--allow-lossy", "--backup-dir", self.base / "backup", "--colors", "2", "--min-psnr", "60", "--target-bytes", "1")
        self.assertEqual(status, 0)
        self.assertEqual(report["files"][0]["status"], "kept-original")
        self.assertIn("below_psnr_floor", report["files"][0]["candidates"][0]["quality_rejections"])
        self.assertEqual(self.path.read_bytes(), self.original)
        self.assertFalse((self.base / "backup").exists())

    def test_soft_target_is_never_a_failure(self):
        report, status = self.run_tool("--target-bytes", "1", "--apply", "--backup-dir", self.base / "backup")
        self.assertEqual(status, 0)
        self.assertEqual(report["files"][0]["status"], "applied")
        self.assertFalse(report["files"][0]["candidates"][0]["under_soft_target"])

    def test_no_saving_keeps_original(self):
        encoded, _ = MODULE.evaluate(self.original, self.image, "png-lossless", self.args())
        self.path.write_bytes(encoded)
        report, status = self.run_tool("--apply", "--backup-dir", self.base / "backup")
        self.assertEqual(status, 0)
        self.assertEqual(report["files"][0]["status"], "kept-original")
        self.assertIn("no_byte_saving", report["files"][0]["candidates"][0]["application_blockers"])

    def test_source_changed_after_evaluation_is_not_overwritten(self):
        encoded, candidate = MODULE.evaluate(self.original, self.image, "png-lossless", self.args())
        self.path.write_bytes(b"new content")
        with self.assertRaisesRegex(ValueError, "source changed"):
            MODULE.apply_candidate(self.path, self.original, encoded, candidate, self.base / "backup", self.root)
        self.assertEqual(self.path.read_bytes(), b"new content")
        self.assertFalse((self.base / "backup").exists())

    def test_backup_failure_prevents_replacement(self):
        with mock.patch.object(MODULE, "write_new", side_effect=OSError("backup blocked")):
            report, status = self.run_tool("--apply", "--backup-dir", self.base / "backup")
        self.assertEqual(status, 1)
        self.assertIn("backup blocked", report["files"][0]["error"])
        self.assertEqual(self.path.read_bytes(), self.original)

    def test_receipt_update_failure_reports_that_image_was_applied(self):
        with mock.patch.object(Path, "write_bytes", side_effect=OSError("journal update blocked")):
            report, status = self.run_tool("--apply", "--backup-dir", self.base / "backup")
        self.assertEqual(status, 0)
        entry = report["files"][0]
        self.assertEqual(entry["status"], "applied")
        self.assertIn("image applied", entry["warning"])
        self.assertEqual(Path(entry["backup"]).read_bytes(), self.original)
        self.assertEqual(json.loads(Path(entry["receipt"]).read_text())["status"], "prepared")
        self.assertNotEqual(self.path.read_bytes(), self.original)

    def test_metadata_chunks_are_preserved(self):
        metadata = PngImagePlugin.PngInfo()
        metadata.add_text("Comment", "source provenance")
        metadata.add(b"gAMA", struct.pack(">I", 45455))
        metadata.add(b"sRGB", b"\x00")
        self.image.save(self.path, pnginfo=metadata, dpi=(144, 144), compress_level=0)
        original = self.path.read_bytes()
        source = MODULE.load_source(original)
        for method in ("png-lossless", "png-rgb", "png-clean-alpha0"):
            with self.subTest(method=method):
                encoded = MODULE.encode(original, source, method, 256, 85)
                ancillary = lambda data: [(name, payload) for name, payload in MODULE.chunks(data) if name[0] & 32]
                self.assertEqual(ancillary(original), ancillary(encoded))
                self.assertEqual(MODULE.decode(encoded).info["Comment"], "source provenance")

    def test_rgb_transparency_key_is_expanded_without_alpha_loss(self):
        image = Image.new("RGB", (4, 4), (13, 26, 39))
        image.putpixel((1, 1), (100, 101, 102))
        image.save(self.path, transparency=(13, 26, 39))
        original = self.path.read_bytes()
        source = MODULE.load_source(original)
        for method in ("png-lossless", "png-rgb", "png-clean-alpha0"):
            encoded = MODULE.encode(original, source, method, 256, 85)
            self.assertTrue(MODULE.metrics(source, MODULE.decode(encoded))["alpha_exact"])

    def test_animation_palette_and_16_bit_inputs_are_rejected(self):
        for mode in ("P", "I;16"):
            with self.subTest(mode=mode):
                buffer = io.BytesIO()
                Image.new(mode, (4, 4)).save(buffer, format="PNG")
                with self.assertRaises(ValueError):
                    MODULE.load_source(buffer.getvalue())
        buffer = io.BytesIO()
        Image.new("RGBA", (4, 4), "red").save(buffer, format="PNG", save_all=True, append_images=[Image.new("RGBA", (4, 4), "blue")], duration=100)
        with self.assertRaisesRegex(ValueError, "animated"):
            MODULE.load_source(buffer.getvalue())

    def test_corrupt_crc_is_rejected(self):
        damaged = bytearray(self.original)
        damaged[-5] ^= 1
        with self.assertRaisesRegex(ValueError, "CRC"):
            MODULE.load_source(bytes(damaged))

    def test_opaque_rgb_lossless_stays_rgb(self):
        self.image.convert("RGB").save(self.path, compress_level=0)
        report, _ = self.run_tool()
        candidate = report["files"][0]["candidates"][0]
        self.assertEqual(candidate["after"]["png_color_type"], 2)
        self.assertTrue(candidate["metrics"]["rgba_exact"])

    def test_opaque_rgb_cleanup_does_not_add_unnecessary_alpha(self):
        self.image.convert("RGB").save(self.path, compress_level=0)
        report, _ = self.run_tool("--method", "png-clean-alpha0")
        self.assertEqual(report["files"][0]["candidates"][0]["after"]["png_color_type"], 2)

    def test_alpha_and_dimension_regressions_block_application(self):
        for changed in (Image.new("RGBA", self.image.size, (0, 0, 0, 0)), Image.new("RGBA", (3, 3), "red")):
            buffer = io.BytesIO()
            changed.save(buffer, format="PNG")
            with mock.patch.object(MODULE, "encode", return_value=buffer.getvalue()):
                report, status = self.run_tool("--apply", "--backup-dir", self.base / "backup")
            self.assertEqual(status, 0)
            self.assertEqual(report["files"][0]["status"], "kept-original")
            self.assertIn("dimensions_or_alpha_changed", report["files"][0]["candidates"][0]["quality_rejections"])
            self.assertEqual(self.path.read_bytes(), self.original)

    def test_metrics_do_not_hide_error_in_transparent_area(self):
        before = Image.new("RGBA", (100, 100))
        after = before.copy()
        before.putpixel((0, 0), (0, 0, 0, 255))
        after.putpixel((0, 0), (30, 30, 30, 255))
        score = MODULE.metrics(before, after)
        self.assertEqual(score["visible_pixels"], 1)
        self.assertEqual(score["visible_rgb_mse"], 900)
        self.assertEqual(score["max_composited_rgb_error"], 30)

    def test_receipt_and_preview_are_explicit_external_outputs(self):
        receipt = self.base / "report.json"
        report, status = self.run_tool("--receipt", receipt, "--preview-dir", self.base / "preview")
        self.assertEqual(status, 0)
        self.assertEqual(json.loads(receipt.read_text()), report)
        self.assertTrue(Path(report["files"][0]["candidates"][0]["preview"]).exists())
        self.assertEqual(self.path.read_bytes(), self.original)
        with self.assertRaises(ValueError):
            self.run_tool("--receipt", receipt)
        with self.assertRaises(ValueError):
            self.run_tool("--preview-dir", self.root / "preview")

    def test_provenance_distinguishes_pixels_from_original_file_bytes(self):
        report, _ = self.run_tool()
        candidate = report["files"][0]["candidates"][0]
        self.assertFalse(candidate["provenance"]["original_bytes_preserved_in_candidate"])
        self.assertTrue(candidate["provenance"]["decoded_pixels_preserved"])
        self.assertNotEqual(candidate["after"]["sha256"], report["files"][0]["before"]["sha256"])

    def test_webp_and_compare_cannot_overwrite_png(self):
        for method in ("compare", "webp-lossless", "webp-lossy"):
            with self.subTest(method=method), self.assertRaises(ValueError):
                self.run_tool("--method", method, "--apply", "--backup-dir", self.base / "backup")

    @unittest.skipUnless(features.check("webp"), "Pillow WebP support unavailable")
    def test_webp_preserves_all_alpha_and_lossless_rgba(self):
        for method in ("webp-lossless", "webp-lossy"):
            encoded, candidate = MODULE.evaluate(self.original, self.image, method, self.args())
            self.assertTrue(candidate["metrics"]["alpha_exact"])
            self.assertEqual(candidate["after"]["dimensions"], [32, 32])
            self.assertFalse(candidate["eligible_for_apply"])
            if method == "webp-lossless":
                self.assertEqual(MODULE.decode(encoded).convert("RGBA").tobytes(), self.image.tobytes())

    def test_unsupported_quality_settings_are_rejected(self):
        for extra in (("--min-psnr", "nan"), ("--min-psnr", "29"), ("--max-error", "65"), ("--colors", "257"), ("--target-bytes", "0")):
            with self.subTest(extra=extra), self.assertRaises(ValueError):
                self.run_tool(*extra)


if __name__ == "__main__":
    unittest.main()
