#!/usr/bin/env python3
"""고정 IDBFS의 진입과 거래 직전에 Web 세션 소유권을 재검사한다."""
import argparse
import hashlib
import os
from pathlib import Path
import tempfile

HASHES = {
    'c41f08d87b6d900c40a5c1c337612620459cdef5fa69c80cb5d4c596df382a12',
    '99fb3102fb48b0cd1b1faba416f20961684e8a1a63b38d748d66e773bb04d5ba',
}
# GL 테이블 보정 후의 release/debug만 허용한다. 엔진 교체는 재검토가 필요하다.
ANCHORS = ('syncfs:(mount,populate,callback)=>{', 'reconcile:(src,dst,callback)=>{')
GUARD = 'if(globalThis.rdStartWithSessionLock?.writeAllowed!==true){return callback(new Error("Web save session ownership lost"));}'

def transform(source: str) -> str:
    original = source
    if GUARD in source:
        if source.count(GUARD) != len(ANCHORS):
            raise ValueError('Incomplete session runtime patch')
        for anchor in ANCHORS:
            if source.count(anchor + GUARD) != 1:
                raise ValueError('Unexpected session runtime patch position')
            original = original.replace(anchor + GUARD, anchor, 1)
    if hashlib.sha256(original.encode()).hexdigest() not in HASHES:
        raise ValueError('Unrecognized pinned runtime after WebGL patch')
    result = original
    for anchor in ANCHORS:
        if result.count(anchor) != 1:
            raise ValueError('Unexpected IDBFS anchor')
        result = result.replace(anchor, anchor + GUARD, 1)
    return result

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('runtime', type=Path)
    args = parser.parse_args()
    p = args.runtime
    temporary = None
    try:
        if p.is_symlink():
            raise ValueError('Refusing symbolic link runtime')
        source = p.read_bytes()
        updated = transform(source.decode()).encode()
        if updated != source:
            mode = p.stat().st_mode & 0o777
            with tempfile.NamedTemporaryFile(dir=p.parent, prefix='.session-runtime-', suffix='.tmp', delete=False) as stream:
                temporary = Path(stream.name)
                stream.write(updated)
                stream.flush()
                os.fsync(stream.fileno())
            temporary.chmod(mode)
            if p.is_symlink() or p.read_bytes() != source:
                raise ValueError('Runtime changed while patching')
            os.replace(temporary, p)
        print(f'Web session runtime verified: {p}')
    except (ValueError, UnicodeError, OSError) as error:
        parser.exit(1, f'Web session runtime patch failed: {error}\n')
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)

if __name__ == '__main__':
    main()
