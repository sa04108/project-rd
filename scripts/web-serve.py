#!/usr/bin/env python3
"""웹 내보내기를 브라우저에서 확인하기 위한 정적 서버입니다."""

from __future__ import annotations

import argparse
import functools
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class WebHandler(SimpleHTTPRequestHandler):
    extensions_map = {
        **SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".pck": "application/octet-stream",
        ".json": "application/json; charset=utf-8",
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Serve a local Godot Web export")
    parser.add_argument("--directory", default="artifacts/web")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=4173)
    args = parser.parse_args()
    root = Path(args.directory).resolve()
    if not (root / "index.html").is_file():
        parser.error(f"{root}/index.html is missing; run scripts/web-export.sh first")
    server = ThreadingHTTPServer((args.host, args.port), functools.partial(WebHandler, directory=str(root)))
    print(f"Serving {root} at http://{args.host}:{args.port}/", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
