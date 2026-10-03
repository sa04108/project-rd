#!/usr/bin/env python3
"""명시한 PNG만 비교하며, 승인된 적용 때에는 저장소 밖에 원본을 보존한다."""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
import os
from pathlib import Path
import stat
import struct
import sys
import tempfile
from datetime import datetime, timezone
import uuid
import zlib

from PIL import Image, ImageChops, features


ROOT = Path(__file__).resolve().parents[2]
METHODS = ("png-lossless", "png-clean-alpha0", "png-rgb", "webp-lossless", "webp-lossy")
LOSSY = {"png-rgb", "webp-lossy"}
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def no_symlinks(path: Path) -> Path:
    """.. 우회와 파일·상위 디렉터리의 심볼릭 링크를 모두 거부한다."""
    if ".." in path.parts:
        raise ValueError(f"parent traversal is not supported: {path}")
    absolute = path.absolute()
    for part in (absolute, *absolute.parents):
        if part.is_symlink():
            raise ValueError(f"symlink skipped: {part}")
    return absolute


def external_path(path: Path, root: Path) -> Path:
    """백업·미리보기·영수증은 저장소 밖의 명시한 경로만 사용한다."""
    absolute = no_symlinks(path)
    if absolute.resolve().is_relative_to(root.resolve()):
        raise ValueError(f"output must be outside repository: {absolute}")
    return absolute


def chunks(data: bytes) -> list[tuple[bytes, bytes]]:
    """PNG 청크의 길이와 CRC를 확인하고 원본 메타데이터를 보존한다."""
    if not data.startswith(PNG_SIGNATURE):
        raise ValueError("input must be a PNG")
    output = []
    offset = len(PNG_SIGNATURE)
    while offset < len(data):
        if offset + 12 > len(data):
            raise ValueError("truncated PNG chunk")
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        end = offset + length + 12
        if end > len(data):
            raise ValueError("truncated PNG payload")
        name = data[offset + 4:offset + 8]
        payload = data[offset + 8:end - 4]
        crc = struct.unpack(">I", data[end - 4:end])[0]
        if zlib.crc32(name + payload) & 0xFFFFFFFF != crc:
            raise ValueError(f"invalid PNG CRC: {name!r}")
        output.append((name, payload))
        offset = end
        if name == b"IEND":
            break
    if not output or output[0][0] != b"IHDR" or output[-1][0] != b"IEND":
        raise ValueError("missing PNG header/end")
    if offset != len(data):
        raise ValueError("trailing bytes after PNG IEND are not supported")
    return output


def pack_chunks(parts: list[tuple[bytes, bytes]]) -> bytes:
    return PNG_SIGNATURE + b"".join(
        struct.pack(">I", len(payload)) + name + payload
        + struct.pack(">I", zlib.crc32(name + payload) & 0xFFFFFFFF)
        for name, payload in parts
    )


def preserve_png_metadata(original: bytes, encoded: bytes) -> bytes:
    """픽셀 청크만 교체하고 색상 프로필·텍스트 등 원본 청크를 유지한다."""
    old = chunks(original)
    new = chunks(encoded)
    header = next(payload for name, payload in new if name == b"IHDR")
    image_chunks = [(name, payload) for name, payload in new if name == b"IDAT"]
    result = []
    inserted = False
    for name, payload in old:
        if name == b"IHDR":
            result.append((name, header))
        elif name == b"IDAT":
            if not inserted:
                result.extend(image_chunks)
                inserted = True
        elif name == b"tRNS" and header[9] == 6:
            continue  # RGBA 출력에서는 투명 색상 키를 실제 알파에 반영했다.
        elif name == b"sBIT" and header[9] == 6 and len(payload) == 3:
            result.append((name, payload + b"\x08"))
        else:
            result.append((name, payload))
    return pack_chunks(result)


def decode(data: bytes) -> Image.Image:
    with Image.open(io.BytesIO(data)) as opened:
        if getattr(opened, "n_frames", 1) != 1:
            raise ValueError("animated images are not supported")
        opened.load()
        image = opened.copy()
        image.format = opened.format
        return image


def load_source(data: bytes) -> Image.Image:
    parts = chunks(data)
    header = parts[0][1]
    if len(header) != 13 or header[8] != 8 or header[9] not in (2, 6):
        raise ValueError("only 8-bit RGB/RGBA PNG inputs are supported")
    if any(name in (b"acTL", b"fcTL", b"fdAT") for name, _ in parts):
        raise ValueError("animated PNG inputs are not supported")
    image = decode(data)
    if image.mode not in ("RGB", "RGBA"):
        raise ValueError(f"unsupported image mode: {image.mode}")
    return image


def snapshot(data: bytes, image: Image.Image) -> dict:
    rgba = image.convert("RGBA")
    alpha = rgba.getchannel("A")
    histogram = alpha.histogram()
    result = {
        "bytes": len(data), "sha256": sha256(data),
        "dimensions": list(image.size), "mode": image.mode, "format": image.format,
        "rgba_sha256": sha256(rgba.tobytes()), "alpha_sha256": sha256(alpha.tobytes()),
        "alpha_extrema": list(alpha.getextrema()), "alpha_zero_pixels": histogram[0],
        "alpha_partial_pixels": sum(histogram[1:255]),
    }
    if data.startswith(PNG_SIGNATURE):
        parts = chunks(data)
        result["png_color_type"] = parts[0][1][9]
        result["ancillary_chunks"] = [name.decode("ascii") for name, _ in parts if name[0] & 32]
    return result


def metrics(before: Image.Image, after: Image.Image) -> dict:
    """투명 면적으로 오차가 희석되지 않도록 보이는 픽셀만 PSNR에 센다."""
    if before.size != after.size:
        return {"dimensions_exact": False, "alpha_exact": False}
    a = before.convert("RGBA")
    b = after.convert("RGBA")
    alpha = a.getchannel("A")
    alpha_exact = alpha.tobytes() == b.getchannel("A").tobytes()
    visible = alpha.point(lambda value: 255 if value else 0)
    count = sum(visible.histogram()[1:])
    difference = ImageChops.difference(a.convert("RGB"), b.convert("RGB"))
    histograms = [channel.histogram(mask=visible) for channel in difference.split()]
    squared_error = sum(i * i * n for histogram in histograms for i, n in enumerate(histogram))
    absolute_error = sum(i * n for histogram in histograms for i, n in enumerate(histogram))
    mse = squared_error / (count * 3) if count else 0.0
    maximum = max((i for histogram in histograms for i, n in enumerate(histogram) if n), default=0)
    composite_max = 0
    for color in ((0, 0, 0, 255), (255, 255, 255, 255)):
        background = Image.new("RGBA", a.size, color)
        original = Image.alpha_composite(background, a).convert("RGB")
        candidate = Image.alpha_composite(background, b).convert("RGB")
        composite_max = max(composite_max, max(high for _, high in ImageChops.difference(original, candidate).getextrema()))
    return {
        "dimensions_exact": True, "alpha_exact": alpha_exact,
        "rgba_exact": a.tobytes() == b.tobytes(), "visible_rgb_exact": squared_error == 0,
        "visible_pixels": count, "visible_rgb_mse": round(mse, 8),
        "visible_rgb_psnr_db": round(10 * math.log10(255 * 255 / mse), 4) if mse else None,
        "psnr_infinite": mse == 0,
        "visible_rgb_mean_absolute_error": round(absolute_error / (count * 3), 8) if count else 0.0,
        "visible_rgb_max_error": maximum, "max_composited_rgb_error": composite_max,
    }


def encode(original: bytes, image: Image.Image, method: str, colors: int, quality: int) -> bytes:
    candidate = image.copy()
    if method == "png-clean-alpha0":
        rgba = image.convert("RGBA")
        transparent = rgba.getchannel("A").point(lambda value: 255 if value == 0 else 0)
        if transparent.getbbox() is not None:
            candidate = rgba
            candidate.paste((0, 0, 0, 0), mask=transparent)
    elif method == "png-rgb":
        rgba = image.convert("RGBA")
        rgb = rgba.convert("RGB")
        transparent = rgba.getchannel("A").point(lambda value: 255 if value == 0 else 0)
        rgb.paste((0, 0, 0), mask=transparent)
        candidate = rgb.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGBA")
        candidate.putalpha(rgba.getchannel("A"))  # 팔레트에 알파를 넣거나 양자화하지 않는다.
    buffer = io.BytesIO()
    if method.startswith("png-"):
        candidate.save(buffer, format="PNG", optimize=True, compress_level=9)
        return preserve_png_metadata(original, buffer.getvalue())
    if not features.check("webp"):
        raise ValueError("Pillow was built without WebP support")
    metadata = {key: image.info[key] for key in ("icc_profile", "exif", "xmp") if image.info.get(key)}
    image.convert("RGBA").save(
        buffer, format="WEBP", lossless=method == "webp-lossless", quality=quality,
        alpha_quality=100, method=6, exact=True, **metadata,
    )
    return buffer.getvalue()


def evaluate(original: bytes, image: Image.Image, method: str, args: argparse.Namespace) -> tuple[bytes, dict]:
    encoded = encode(original, image, method, args.colors, args.webp_quality)
    decoded = decode(encoded)
    score = metrics(image, decoded)
    reasons = []
    if not score["dimensions_exact"] or not score["alpha_exact"]:
        reasons.append("dimensions_or_alpha_changed")
    if method in ("png-lossless", "webp-lossless") and not score.get("rgba_exact"):
        reasons.append("lossless_pixels_changed")
    if method == "png-clean-alpha0" and not score.get("visible_rgb_exact"):
        reasons.append("visible_pixels_changed")
    if method in LOSSY:
        psnr = score.get("visible_rgb_psnr_db")
        if psnr is not None and psnr < args.min_psnr:
            reasons.append("below_psnr_floor")
        if score.get("max_composited_rgb_error", 256) > args.max_error:
            reasons.append("above_composited_error_limit")
    quality_pass = not reasons
    application_blockers = []
    if method.startswith("webp-"):
        application_blockers.append("format_migration_requires_separate_reference_and_import_review")
    if args.role == "runtime" and method != "png-lossless":
        application_blockers.append("runtime_requires_pixel_exact_png")
    if method in LOSSY and not args.allow_lossy:
        application_blockers.append("allow_lossy_not_selected")
    if method == "png-clean-alpha0" and not args.allow_transparent_rgb_cleanup:
        application_blockers.append("allow_transparent_rgb_cleanup_not_selected")
    if len(encoded) >= len(original):
        application_blockers.append("no_byte_saving")
    return encoded, {
        "method": method, "after": snapshot(encoded, decoded), "metrics": score,
        "saved_bytes": len(original) - len(encoded),
        "saved_percent": round(100 * (len(original) - len(encoded)) / len(original), 3),
        "under_soft_target": len(encoded) <= args.target_bytes,
        "quality_pass": quality_pass, "quality_rejections": reasons,
        "application_blockers": application_blockers,
        "eligible_for_apply": quality_pass and not application_blockers,
        "metadata_note": (
            "PNG ancillary chunks are retained; RGB transparency keys become exact alpha in RGBA output."
            if method.startswith("png-") else
            "ICC/EXIF/XMP are copied when present; PNG gamma/chromaticity/resolution chunks are not automatically translated. Inspect color-managed rendering before migration."
        ),
        "provenance": {
            "original_bytes_preserved_in_candidate": original == encoded,
            "decoded_pixels_preserved": score.get("rgba_exact", False),
            "alpha_preserved": score["alpha_exact"],
            "required_updates_if_adopted": [
                "Record original and derived SHA-256, method, settings, dimensions, alpha hash, and backup location.",
                "Update any source/review/pipeline receipts referring to the replaced file hash; do not call transcoded bytes an untouched generation original.",
                "Review downstream extraction/rendering; existing Git history is not rewritten by this tool.",
            ],
        },
    }


def write_new(path: Path, data: bytes) -> None:
    no_symlinks(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    no_symlinks(path)
    with path.open("xb") as output:
        output.write(data)
        output.flush()
        os.fsync(output.fileno())


def json_bytes(value: dict) -> bytes:
    return (json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + "\n").encode("utf-8")


def apply_candidate(path: Path, original: bytes, encoded: bytes, receipt: dict, backup_root: Path, root: Path) -> dict:
    """변경 직전에 원본을 재확인하고 검증된 외부 백업 뒤 원자적으로 교체한다."""
    no_symlinks(path)
    external_path(backup_root, root)
    if path.read_bytes() != original:
        raise ValueError(f"source changed since evaluation: {path}")
    info = path.stat()
    relative = path.relative_to(root)
    backup = backup_root / "originals" / relative
    write_new(backup, original)
    if sha256(backup.read_bytes()) != sha256(original):
        raise ValueError(f"backup verification failed: {backup}")
    record = dict(receipt, status="prepared", backup=str(backup))
    journal = backup.with_name(backup.name + ".receipt.json")
    write_new(journal, json_bytes(record))
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(prefix=f".{path.name}.optimize-", suffix=".tmp", dir=path.parent, delete=False) as output:
            temporary = Path(output.name)
            output.write(encoded)
            output.flush()
            os.fsync(output.fileno())
        os.chmod(temporary, stat.S_IMODE(info.st_mode))
        no_symlinks(path)
        if path.read_bytes() != original or path.stat().st_ino != info.st_ino:
            raise ValueError(f"source changed before replacement: {path}")
        os.replace(temporary, path)
        temporary = None
        if sha256(path.read_bytes()) != sha256(encoded):
            raise ValueError(f"replacement verification failed; restore from {backup}")
        record["status"] = "applied"
        try:
            journal.write_bytes(json_bytes(record))
        except OSError as error:
            return {
                "backup": str(backup), "receipt": str(journal),
                "warning": f"image applied; receipt status update failed: {error}; prepared receipt contains both hashes",
            }
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    return {"backup": str(backup), "receipt": str(journal)}


def parser() -> argparse.ArgumentParser:
    cli = argparse.ArgumentParser(description="Compare explicitly named PNGs; default is read-only lossless PNG analysis. 1 MB is a soft target, never a failure.")
    cli.add_argument("paths", type=Path, nargs="+", help="explicit PNG files inside this repository; no directory traversal")
    cli.add_argument("--method", choices=(*METHODS, "compare"), default="png-lossless")
    cli.add_argument("--role", choices=("runtime", "source", "background"), default="runtime")
    cli.add_argument("--apply", action="store_true", help="replace eligible PNGs only, after verified external backups")
    cli.add_argument("--backup-dir", type=Path, help="required for --apply; outside repository")
    cli.add_argument("--preview-dir", type=Path, help="explicitly export comparison copies outside repository")
    cli.add_argument("--receipt", type=Path, help="explicitly save JSON receipt outside repository; stdout is always JSON")
    cli.add_argument("--allow-lossy", action="store_true", help="allow PNG RGB palette reduction for source/background roles")
    cli.add_argument("--allow-transparent-rgb-cleanup", action="store_true", help="allow hidden RGB changes for source/background roles; inspect filtered edges")
    cli.add_argument("--colors", type=int, default=256)
    cli.add_argument("--webp-quality", type=int, default=85)
    cli.add_argument("--min-psnr", type=float, default=38.0, help="visible-pixel RGB PSNR floor, 30..60 dB; infinity passes")
    cli.add_argument("--max-error", type=int, default=48, help="maximum RGB error after black/white compositing, 1..64")
    cli.add_argument("--target-bytes", type=int, default=1_000_000, help="informational soft target only; no resizing or forced quality reduction")
    return cli


def validate(args: argparse.Namespace, root: Path) -> None:
    if not 2 <= args.colors <= 256 or not 0 <= args.webp_quality <= 100:
        raise ValueError("colors must be 2..256 and WebP quality 0..100")
    if not math.isfinite(args.min_psnr) or not 30 <= args.min_psnr <= 60 or not 1 <= args.max_error <= 64:
        raise ValueError("PSNR floor must be 30..60 dB and maximum error 1..64")
    if args.target_bytes <= 0:
        raise ValueError("soft target must be positive")
    for name in ("backup_dir", "preview_dir", "receipt"):
        path = getattr(args, name)
        if path is not None:
            setattr(args, name, external_path(path, root))
    if args.receipt is not None and args.receipt.exists():
        raise ValueError(f"receipt already exists: {args.receipt}")
    if args.apply:
        if args.backup_dir is None:
            raise ValueError("--apply requires --backup-dir outside the repository")
        if args.method == "compare" or args.method.startswith("webp-"):
            raise ValueError("--apply supports a single PNG method only; WebP is comparison/export-only")
        if args.role == "runtime" and args.method != "png-lossless":
            raise ValueError("runtime assets require png-lossless; hidden RGB cleanup and quantization are not runtime defaults")
        if args.method in LOSSY and not args.allow_lossy:
            raise ValueError("RGB reduction requires --allow-lossy and a source/background role")
        if args.method == "png-clean-alpha0" and not args.allow_transparent_rgb_cleanup:
            raise ValueError("hidden RGB cleanup requires --allow-transparent-rgb-cleanup")


def run(args: argparse.Namespace, root: Path = ROOT) -> tuple[dict, int]:
    root = root.resolve()
    validate(args, root)
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:10]
    methods = METHODS if args.method == "compare" else (args.method,)
    report = {
        "schema_version": 1, "run_id": run_id, "mode": "apply" if args.apply else "dry-run",
        "repository": str(root), "soft_target_bytes": args.target_bytes,
        "target_policy": "recommendation_only; keep larger files whenever quality or compatibility requires it",
        "settings": {key: getattr(args, key) for key in ("method", "role", "colors", "webp_quality", "min_psnr", "max_error", "allow_lossy", "allow_transparent_rgb_cleanup")},
        "files": [],
    }
    errors = 0
    seen = set()
    for raw_path in args.paths:
        entry = {"path": str(raw_path), "status": "pending"}
        report["files"].append(entry)
        try:
            path = no_symlinks(raw_path)
            if path in seen:
                entry.update(status="skipped", reason="duplicate explicit path")
                continue
            seen.add(path)
            if not path.is_relative_to(root):
                raise ValueError(f"input must be inside repository: {path}")
            if not path.is_file() or path.suffix.lower() != ".png":
                raise ValueError(f"explicit PNG file required: {path}")
            relative = path.relative_to(root)
            original = path.read_bytes()
            image = load_source(original)
            entry.update(path=str(relative), before=snapshot(original, image), candidates=[])
            selected = None
            for method in methods:
                encoded, candidate = evaluate(original, image, method, args)
                if args.preview_dir is not None:
                    suffix = ".webp" if method.startswith("webp-") else ".png"
                    preview = args.preview_dir / run_id / relative.parent / (relative.name + "." + method + suffix)
                    write_new(preview, encoded)
                    candidate["preview"] = str(preview)
                entry["candidates"].append(candidate)
                if method == args.method:
                    selected = (encoded, candidate)
            entry["status"] = "analyzed"
            if args.apply and selected is not None:
                encoded, candidate = selected
                if candidate["eligible_for_apply"]:
                    record = {"source": str(relative), "before": entry["before"], "candidate": candidate, "settings": report["settings"]}
                    applied = apply_candidate(path, original, encoded, record, args.backup_dir / run_id, root)
                    entry.update(status="applied", **applied)
                else:
                    entry.update(status="kept-original", reason="quality, compatibility, or no-byte-saving gate")
        except (OSError, ValueError, SyntaxError, Image.DecompressionBombError) as error:
            if str(error).startswith("symlink skipped:"):
                entry.update(status="skipped", reason=str(error))
            else:
                entry.update(status="error", error=str(error))
                errors += 1
    report["error_count"] = errors
    if args.receipt is not None:
        write_new(args.receipt, json_bytes(report))
    return report, 1 if errors else 0


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        report, status = run(args)
        print(json_bytes(report).decode("utf-8"), end="")
        return status
    except (OSError, ValueError) as error:
        print(f"image optimization: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
