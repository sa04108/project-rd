#!/usr/bin/env python3
"""sprite-gen의 보존된 중간 프롬프트 템플릿에 개별 캐릭터 계약을 적용한다."""
from pathlib import Path
import argparse,json
ROOT=Path(__file__).resolve().parents[2]

def prepare(identity,state):
    plan=json.loads((ROOT/'tools/art/identity-plan.json').read_text())
    entry=next(e for e in plan['identities'] if e['id']==identity)
    if state not in entry['required_states']:raise ValueError('요청한 상태는 이 캐릭터의 제작 계획에 없습니다')
    family=entry['family']
    template=ROOT/f'assets/art/families/{family}/sprite_run/prompts/{state}.txt'
    prompt=template.read_text().replace(f'`family_{family}`',f'`{identity}`')
    start=prompt.index('Character:');end=prompt.index('\n\nUse this prompt',start)
    description=f"The exact attached reference portrait for {identity}, {entry['name']}. "+' '.join(entry['anatomy_weapon_safeguards'])
    prompt=prompt[:start]+f'Character: {description}\nStyle contract: Preserve the exact attached character identity, detailed pixel-art rendering, face, material, outfit, silhouette, palette, proportions and camera. Do not mirror, rotate camera, redesign equipment or add props.'+prompt[end:]
    start=prompt.index('Animation action:');end=prompt.index('\n\nAnchor lock:',start)
    motion=entry['states'][state]['motion_prompt']
    if state=='attack':motion+=' Frames 1–2 are anticipation; frame 3 is the decisive impact/release; frame 4 follows through; frames 5–6 recover. The weapon remains visible and physically held except an intentional empty throwing-hand release. No detached projectile or effect.'
    elif state=='idle':motion+=' Six genuinely distinct but SUBTLE continuous idle phases. No attack, travel, frame-to-frame redesign or transformed copies.'
    else:motion+=' Six truly alternating locomotion phases, coherent feet contacts or wings/soft-body motion appropriate to this anatomy. This is NOT an attack. Game code supplies forward travel; keep the character centered.'
    prompt=prompt[:start]+'Animation action: '+motion+prompt[end:]
    start=prompt.index('Layout requirements:')
    prompt=prompt[:start]+'''Layout requirements (explicit sprite-gen row-layout adaptation for built-in generation):
- Exactly SIX full-body poses in THREE columns and TWO rows, reading top-left to bottom-right.
- Landscape 3:2 image, ideally1536x1024. Six equal square invisible slots. Reference2 is layout-only.
- Make each WHOLE figure INCLUDING all weapons, wings, tails, antlers and ornaments no larger than70 percent of one square slot. At least15 percent transparent padding on every side. No cross-slot pixels, no clipping.
- Keep body scale identical in all six poses. Center hips/torso in its own slot and keep foot/ground baseline at86 percent slot height. Do not grow the whole sprite to fill a pose's empty space.
- Full real transparent alpha background. This replaces the upstream magenta option. No fake checkerboard, guide lines, text, numbers, labels, scenery, floor, shadows or halos.
- Clean hard sprite edges, faithful reference pixel-art rendering. No motion blur or detached decoration.
- Existing identity-defining floating ornaments may remain exactly as in the reference, wholly inside that character's cell. Do not replace legitimate anatomy with a generic family design.
Output only the six-pose sprite sheet image.
'''
    directory=ROOT/'docs/art-generation'/identity;directory.mkdir(parents=True,exist_ok=True)
    out=directory/f'{state}.prompt.txt'
    if out.exists():raise FileExistsError(f'기존 실제 전송 프롬프트를 덮어쓰지 않습니다: {out}')
    out.write_text(prompt)
    print(out.relative_to(ROOT))
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('identity');p.add_argument('--state',required=True,choices=['attack','walk','idle']);a=p.parse_args();prepare(a.identity,a.state)
