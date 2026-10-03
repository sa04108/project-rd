#!/usr/bin/env python3
"""생성된 여섯 자세를 자르거나 변형하지 않고 균일 배율의 런타임 셀로 패킹한다."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image
from scipy.ndimage import label, find_objects

ROOT = Path(__file__).resolve().parents[2]

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def pack(identity, state, grid=False, ornaments=False):
    source = ROOT / 'docs/art-generation' / identity / f'{state}.source.png'
    image = Image.open(source).convert('RGBA')
    alpha = np.array(image)[:, :, 3]
    labels, _ = label(alpha > 128, np.ones((3, 3)))
    counts = np.bincount(labels.ravel())
    largest = np.argsort(counts[1:])[-6:] + 1
    if len(largest) != 6 or min(counts[largest]) < 1000:
        raise ValueError('여섯 개의 독립된 자세를 확인할 수 없습니다')
    slices = find_objects(labels)
    records = []
    for component in largest:
        yy, xx = slices[component - 1]
        if xx.start == 0 or yy.start == 0 or xx.stop == image.width or yy.stop == image.height:
            raise ValueError('원본 가장자리에서 잘린 자세가 있습니다')
        # 하단 발 영역의 중심으로 무기 길이에 따른 좌우 흔들림을 피한다.
        foot = labels[max(yy.start, yy.stop - 24):yy.stop] == component
        foot_x = np.where(foot)[1]
        anchor_x = (int(foot_x.min()) + int(foot_x.max()) + 1) / 2
        box = (max(0,xx.start-4),max(0,yy.start-4),min(image.width,xx.stop+4),min(image.height,yy.stop+4))
        records.append({'box':box,'anchor_x':anchor_x,'ground_y':yy.stop,'center':((xx.start+xx.stop)/2,(yy.start+yy.stop)/2)})
    if ornaments:
        # 부유 수정·기포처럼 원화의 일부인 연결되지 않은 장식을 가까운 본체에 배정한다.
        for component in range(1,len(counts)):
            if component in largest or counts[component]<8:
                continue
            yy,xx=slices[component-1]
            center=((xx.start+xx.stop)/2,(yy.start+yy.stop)/2)
            record=min(records,key=lambda r:(r['center'][0]-center[0])**2+(r['center'][1]-center[1])**2)
            distance=((record['center'][0]-center[0])**2+(record['center'][1]-center[1])**2)**0.5
            if distance>max(image.width/3,image.height/2)*0.7:
                raise ValueError('본체에서 너무 먼 연결되지 않은 픽셀이 있습니다')
            left,top,right,bottom=record['box']
            record['box']=(max(0,min(left,xx.start-4)),max(0,min(top,yy.start-4)),min(image.width,max(right,xx.stop+4)),min(image.height,max(bottom,yy.stop+4)))
    records.sort(key=lambda r:r['center'][1])
    records = sorted(records[:3],key=lambda r:r['center'][0]) + sorted(records[3:],key=lambda r:r['center'][0])
    if grid:
        records = []
        for row in range(2):
            for col in range(3):
                x0=round(col*image.width/3);x1=round((col+1)*image.width/3)
                y0=round(row*image.height/2);y1=round((row+1)*image.height/2)
                mask=Image.fromarray((alpha[y0:y1,x0:x1]>128).astype('uint8')*255)
                box=mask.getbbox()
                if box is None or box[0]<2 or box[1]<2 or box[2]>x1-x0-2 or box[3]>y1-y0-2:
                    raise ValueError('격자 경계와 자세가 겹칩니다')
                left,top,right,bottom=box
                records.append({'box':(max(x0,x0+left-4),max(y0,y0+top-4),min(x1,x0+right+4),min(y1,y0+bottom+4)), 'anchor_x':(x0+x1)/2,'ground_y':y0+bottom,'center':((x0+x1)/2,(y0+y1)/2)})
    # 서로 다른 자세의 픽셀이 사각 잘라내기에 섞이지 않음을 확인한다.
    for i,a in enumerate(records):
        for b in records[i+1:]:
            ax,ay,bx,by=a['box'];cx,cy,dx,dy=b['box']
            if min(bx,dx)>max(ax,cx) and min(by,dy)>max(ay,cy):
                raise ValueError('자세 영역이 겹칩니다. 수동 검토가 필요합니다')
    scale = min(min(112/max(r['anchor_x']-r['box'][0],r['box'][2]-r['anchor_x']),208/(r['ground_y']-r['box'][1])) for r in records)
    atlas = Image.new('RGBA',(768,512),(0,0,0,0))
    cells=[]
    for i,r in enumerate(records):
        x0,y0,x1,y1=r['box']
        crop=image.crop(r['box'])
        resized=crop.resize((max(1,round(crop.width*scale)),max(1,round(crop.height*scale))),Image.Resampling.NEAREST)
        dx=round(128-(r['anchor_x']-x0)*scale);dy=round(232-(r['ground_y']-y0)*scale)
        if dx<0 or dy<0 or dx+resized.width>256 or dy+resized.height>256:
            raise ValueError('정규화된 자세가 셀을 벗어납니다')
        atlas.alpha_composite(resized,(i%3*256+dx,i//3*256+dy))
        cells.append({'x':i%3*256,'y':i//3*256,'w':256,'h':256})
    target=ROOT/'assets/art/identities'/identity;target.mkdir(parents=True,exist_ok=True)
    portrait=Image.open(ROOT/f'assets/art/portraits/{identity}.png').convert('RGBA')
    pb=portrait.getchannel('A').getbbox()
    ready_height=(records[-1]['ground_y']-records[-1]['box'][1])*scale
    render_scale=(pb[3]-pb[1])/ready_height
    layout_path=target/'layout.json'
    old=json.loads(layout_path.read_text()) if layout_path.exists() else None
    old_states=[] if old is None else [s for s in old['frame_layout']['rows'] if s!=state]
    combined=Image.new('RGBA',(768,512*(len(old_states)+1)),(0,0,0,0))
    rows={};animations={}
    if old_states:
        previous=Image.open(target/'atlas.png').convert('RGBA')
        for group,old_state in enumerate(old_states):
            rows[old_state]=[]
            for i,cell in enumerate(old['frame_layout']['rows'][old_state]):
                tile=previous.crop((cell['x'],cell['y'],cell['x']+cell['w'],cell['y']+cell['h']))
                x=i%3*256;y=group*512+i//3*256
                combined.alpha_composite(tile,(x,y));rows[old_state].append({'x':x,'y':y,'w':256,'h':256})
            animations[old_state]=old['animation']['rows'][old_state]
    offset=len(old_states)*512
    combined.alpha_composite(atlas,(0,offset))
    rows[state]=[dict(cell,y=cell['y']+offset) for cell in cells]
    animations[state]={'frames':6,'fps':8 if state!='idle' else 4,'loop':state!='attack','render_scale':round(render_scale,6),'durations_ms':[90,90,60,60,180,180] if state=='attack' else ([250]*6 if state=='idle' else [125]*6)}
    layout={'schema':1,'cell':{'width':256,'height':256},'frame_layout':{'sheetWidth':768,'sheetHeight':combined.height,'rows':rows},'animation':{'rows':animations}}
    combined.save(target/'atlas.png')
    (target/'layout.json').write_text(json.dumps(layout,ensure_ascii=False,indent=2)+'\n')
    receipt={'identity':identity,'state':state,'source':str(source.relative_to(ROOT)),'source_sha256':digest(source),'prompt_sha256':digest(source.with_name(f'{state}.prompt.txt')),'generator':'built-in image tool','image_model_id':None,'sprite_gen_source_commit':'4a2ebdbcbb9e228b143ef10876ecd48261288df0','source_dimensions':image.size,'packing':'6 connected full poses, single uniform scale, feet baseline232; no repainted pixels','uniform_scale':scale,'source_regions':records,'atlas_sha256':digest(target/'atlas.png'),'review':'agent visually inspected all six poses; runtime review pending'}
    receipts_path=target/'receipt.json'
    receipts=json.loads(receipts_path.read_text()) if receipts_path.exists() else {'identity':identity,'states':{}}
    if 'states' not in receipts:
        receipts={'identity':identity,'states':{receipts['state']:receipts}}
    receipts['states'][state]=receipt
    receipts_path.write_text(json.dumps(receipts,ensure_ascii=False,indent=2)+'\n')
    manifest_path=ROOT/'assets/art/identity_animations.json'
    manifest=json.loads(manifest_path.read_text()) if manifest_path.exists() else {'schema':1,'identities':{}}
    manifest['identities'][identity]={'atlas':str((target/'atlas.png').relative_to(ROOT)),'frame_layout':str((target/'layout.json').relative_to(ROOT))}
    manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    print(f'{identity}/{state}: 6 poses packed; scale={scale:.3f}; render_scale={render_scale:.3f}')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('identity');parser.add_argument('--state',default='attack',choices=['attack','walk','idle'])
    parser.add_argument('--grid',action='store_true');parser.add_argument('--ornaments',action='store_true');args=parser.parse_args();pack(args.identity,args.state,args.grid,args.ornaments)
