#!/usr/bin/env python3
"""실제 번역과 언어 이름에 필요한 CJK 글리프를 추려 배포 폰트를 만든다."""
import argparse
import hashlib
import json
from pathlib import Path
from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[2]

def build(source: Path, locale: str, suffix: str) -> dict:
    messages = json.loads((ROOT / 'data/localization.json').read_text())
    text = ''.join(entry[locale] for entry in messages.values())
    text += 'English한국어简体中文日本語' + ''.join(chr(c) for c in range(32, 127))
    text += '★♥◇◈×▶Ⅱ©·–−…'
    font = TTFont(source, recalcTimestamp=False)
    cmap = font.getBestCmap()
    # 한글·기호는 기존 폰트 fallback도 쓰지만 해당 언어 번역 본문은 전부 포함해야 한다.
    fallback = set(TTFont(ROOT / 'assets/fonts/GuildSymbols.ttf').getBestCmap())
    missing = sorted({c for entry in messages.values() for c in entry[locale] if not c.isspace() and ord(c) not in cmap and ord(c) not in fallback})
    if missing:
        raise ValueError(f'{locale} 원본 폰트에 없는 문자: {missing}')
    options = subset.Options()
    options.layout_features = ['*']
    options.name_IDs = [0, 1, 2, 3, 4, 5, 6, 13, 14]
    options.recalc_timestamp = False
    builder = subset.Subsetter(options=options)
    builder.populate(unicodes={ord(c) for c in text if ord(c) in cmap})
    builder.subset(font)
    family = f'FRD Sans {suffix}'
    for record in font['name'].names:
        if record.nameID in [1, 3, 4, 6]:
            value = family.replace(' ', '') if record.nameID == 6 else family
            record.string = value.encode(record.getEncoding())
    if 'CFF ' in font:
        font['CFF '].cff.fontNames = [family.replace(' ', '')]
        top = font['CFF '].cff.topDictIndex[0]
        top.FamilyName = family
        top.FullName = family
    destination = ROOT / f'assets/fonts/GuildCjk{suffix}.otf'
    font.save(destination)
    return {'locale': locale, 'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
            'output': str(destination.relative_to(ROOT)), 'bytes': destination.stat().st_size,
            'glyphs': len(font.getBestCmap()), 'sha256': hashlib.sha256(destination.read_bytes()).hexdigest()}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sc', type=Path, required=True)
    parser.add_argument('--jp', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps([build(args.sc, 'zh_CN', 'SC'), build(args.jp, 'ja', 'JP')], ensure_ascii=False, indent=2))

if __name__ == '__main__':
    main()
