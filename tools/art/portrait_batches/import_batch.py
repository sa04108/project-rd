#!/usr/bin/env python3
"""공식 sprite-gen 정적 컷 추출을 실행하고 비어 있거나 잘린 결과를 거부한다."""
import argparse
import json
import shutil
import subprocess
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('batch', type=int, choices=range(1, 7))
parser.add_argument('sheet', type=Path)
parser.add_argument('--sprite-gen', default='/workspace/.tools/sprite-gen/.venv/bin/sprite-gen')
args = parser.parse_args()
packet = json.loads((Path(__file__).parent / f'batch-{args.batch}.json').read_text())
source = root / 'assets/art/portraits/batches' / f'batch-{args.batch}.png'
source.parent.mkdir(parents=True, exist_ok=True)
if args.sheet.resolve() != source.resolve():
    shutil.copy2(args.sheet, source)
out = root / 'assets/art/portraits' / f'batch-{args.batch}'
command = [args.sprite_gen, 'slice-sheet', '--sheet', str(source), '--out-dir', str(out),
           '--chroma-key', '#FF00FF', '--grid', packet['grid'], '--names', ','.join(packet['ids']),
           '--cell-width', '384', '--cell-height', '256', '--baseline-y', '236', '--target-height', '208']
subprocess.run(command, check=True)
for identity in packet['ids']:
    path = out / f'{identity}.png'
    with Image.open(path) as image:
        box = image.getchannel('A').getbbox()
        if image.size != (384, 256) or not box or box[0] <= 0 or box[1] <= 0 or box[2] >= 384 or box[3] >= 256:
            raise ValueError(f'{identity}: 빈 프레임 또는 캔버스 경계 잘림: {box}')
        if box[3] - box[1] < 200:
            raise ValueError(f'{identity}: 예상보다 작은 피사체: {box}')
for identity in packet['ids']:
    shutil.copy2(out / f'{identity}.png', root / 'assets/art/portraits' / f'{identity}.png')
(out / '.gdignore').touch()
receipt = {'pipeline': 'sprite-gen slice-sheet', 'sprite_gen_version': '2.17.0', 'batch': args.batch,
           'ids': packet['ids'], 'alpha_bounds_check': 'passed', 'canvas': [384, 256],
           'baseline_y': 236, 'target_height': 208, 'manual_visual_review': 'pending',
           'generation_route': 'conversation image_gen', 'image_model_id': 'not exposed'}
(out / 'receipt.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n')
print(f'PORTRAIT_BATCH_PASS {args.batch}: {len(packet["ids"])} visible RGBA assets')
