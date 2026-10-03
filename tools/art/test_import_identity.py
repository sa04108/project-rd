#!/usr/bin/env python3
"""프레임 패킹의 상태 병합, 경계, 알파 및 반복 실행 계약을 검사한다."""
import importlib.util,json,tempfile,unittest
from pathlib import Path
from PIL import Image,ImageDraw
spec=importlib.util.spec_from_file_location('import_identity',Path(__file__).with_name('import_identity.py'))
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class PackingContract(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);self.previous=module.ROOT;module.ROOT=self.root
        self.addCleanup(setattr,module,'ROOT',self.previous)
        source=self.root/'docs/art-generation/u01';source.mkdir(parents=True)
        portraits=self.root/'assets/art/portraits';portraits.mkdir(parents=True)
        portrait=Image.new('RGBA',(256,256));ImageDraw.Draw(portrait).ellipse((80,30,170,230),fill='white');portrait.save(portraits/'u01.png')
        for state in ['attack','idle']:
            image=Image.new('RGBA',(600,400));draw=ImageDraw.Draw(image)
            for i in range(6):
                x=i%3*200;y=i//3*200
                draw.ellipse((x+50+i,y+40,x+150,y+170),fill=(100+i*20,50,200,255))
            image.save(source/f'{state}.source.png');(source/f'{state}.prompt.txt').write_text('fixture')
    def test_merge_preserves_existing_attack(self):
        module.pack('u01','attack');target=self.root/'assets/art/identities/u01'
        before=Image.open(target/'atlas.png').tobytes()
        module.pack('u01','idle')
        layout=json.loads((target/'layout.json').read_text())
        self.assertEqual(set(layout['frame_layout']['rows']),{'attack','idle'})
        self.assertEqual(Image.open(target/'atlas.png').crop((0,0,768,512)).tobytes(),before)
        self.assertEqual(layout['animation']['rows']['attack']['durations_ms'],[90,90,60,60,180,180])
        self.assertTrue(layout['animation']['rows']['idle']['loop'])
        module.pack('u01','idle');self.assertEqual(Image.open(target/'atlas.png').size,(768,1024))
    def test_six_cells_alpha_and_bounds(self):
        module.pack('u01','attack',True);target=self.root/'assets/art/identities/u01'
        atlas=Image.open(target/'atlas.png');layout=json.loads((target/'layout.json').read_text())
        self.assertEqual(atlas.mode,'RGBA');self.assertEqual(atlas.getpixel((0,0))[3],0)
        cells=layout['frame_layout']['rows']['attack'];self.assertEqual(len(cells),6)
        for cell in cells:
            a=atlas.crop((cell['x'],cell['y'],cell['x']+256,cell['y']+256)).getchannel('A');box=a.getbbox()
            self.assertIsNotNone(box);self.assertGreater(box[0],0);self.assertGreater(box[1],0);self.assertLess(box[2],256);self.assertLess(box[3],256)
    def test_reject_missing_poses(self):
        source=self.root/'docs/art-generation/u01/attack.source.png'
        Image.new('RGBA',(600,400)).save(source)
        with self.assertRaises(ValueError):module.pack('u01','attack')
    def test_reject_clipped_figure(self):
        source=self.root/'docs/art-generation/u01/attack.source.png';image=Image.open(source)
        ImageDraw.Draw(image).rectangle((0,40,100,170),fill='white');image.save(source)
        with self.assertRaises(ValueError):module.pack('u01','attack')
if __name__=='__main__':unittest.main()
