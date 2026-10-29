"""ROI-only experiment: no model import, weight load, inference or network access."""
from pathlib import Path
from datetime import datetime, timezone
import csv
import hashlib
import json
import math

import argparse
_PARSER = argparse.ArgumentParser(description=__doc__)
_PARSER.add_argument('--data-root', type=Path, required=True, help='External experiment data root; never the Git checkout')
_PARSER.add_argument('--output-dir', type=Path, required=True, help='New external experiment directory; must not exist')
_PARSER.add_argument('--official-source', type=Path, help='Existing official 6DRepNet360 checkout')
_PARSER.add_argument('--video', type=Path, help='Explicit source video override, never rewritten')
_PARSER.add_argument('--weights', type=Path, help='Existing local weights override; hash checks remain required')
_PARSER.add_argument('--annotations', type=Path, help='Existing manual working-copy JSON override')
_PARSER.add_argument('--roi-dir', type=Path, help='Existing C ROI audit directory')
_PARSER.add_argument('--raw-dir', type=Path, help='Existing full-clip CPU experiment directory')
_ARGS = _PARSER.parse_args()
ROOT = _ARGS.data_root.resolve()
OUT = _ARGS.output_dir.resolve()
if not ROOT.is_dir(): raise ValueError('External data root does not exist')
if OUT == ROOT or ROOT not in OUT.parents: raise ValueError('Output must be a new directory within external data root')
REPO = Path(__file__).resolve().parents[2]
if OUT == REPO or REPO in OUT.parents: raise ValueError('Keep experiment outputs outside the Git checkout')
OUT.mkdir(parents=True, exist_ok=False)
AUDIT = (_ARGS.roi_dir or ROOT/'outputs/d01_headpose_6drepnet360/roi_adaylari_20261029T073859Z').resolve()
SOURCE = (_ARGS.official_source or ROOT/'dis_kaynaklar/6DRepNet360').resolve()
WEIGHTS = (_ARGS.weights or ROOT/'araclar/6DRepNet360_Full-Rotation_300W_LP+Panoptic.pth').resolve()
MANUAL = (_ARGS.annotations or ROOT/'calisma/d01_inceleme_20261029_001519_6423955a35554b9aa6fbf333c195d6fd/d01_ilk_ornek_taslak.json').resolve()
AUDIT = (_ARGS.roi_dir or ROOT/'outputs/d01_headpose_6drepnet360/roi_zaman_20261028T220317_762182Z_0d3227df').resolve()
PRIOR = ROOT/'outputs/d01_headpose_6drepnet360/tum_klip_20261028T222015_076401Z_835cf906'
CANDIDATES = [
    dict(id='A_dar_dolgusuz', x=290, y=0, width=360, height=360, padding='none'),
    dict(id='B_genis_dolgusuz', x=250, y=0, width=440, height=440, padding='none'),
    dict(id='C_ust40_acik_dolgu', x=250, y=-40, width=440, height=440,
         padding='explicit top 40 source pixels, constant RGB(128,128,128); synthetic area, not scene evidence'),
]

def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as f:
        for block in iter(lambda: f.read(1024*1024), b''): h.update(block)
    return h.hexdigest()

def write_json(name, data):
    (OUT/name).write_text(json.dumps(data, ensure_ascii=False, indent=2, allow_nan=False)+'\n', encoding='utf-8')

def main():
    if (OUT/'ayarlar.json').exists(): raise RuntimeError('Do not overwrite a previous experiment.')
    info = json.loads((AUDIT/'report.json').read_text(encoding='utf-8'))
    if _ARGS.video: info['video_path'] = str(_ARGS.video.resolve())
    info['weight_path'] = str(WEIGHTS)
    protected = {}  # Build a current-machine manifest; old absolute paths are historical only
    for base in (AUDIT, PRIOR):
        protected.update({str(p.resolve()):digest(p) for p in base.rglob('*') if p.is_file()})
    for p in (ROOT/'araclar').glob('d01*.py'): protected[str(p.resolve())] = digest(p)
    note = ROOT/'mobil_rag_223bc7d/mobile_skeleton/docs/DEVAM_NOTU.md'
    protected[str(note)] = digest(note)
    protected.update({str(p):digest(p) for p in (Path(info['video_path']), WEIGHTS, MANUAL)})
    write_json('koruma_manifesti.json', protected)
    assert digest(info['video_path']) == info['video_sha256']
    assert digest(info['weight_path']) == info['weight_sha256']
    import cv2
    import torch
    from PIL import Image, ImageDraw
    from torchvision import transforms
    torch.set_num_threads(2)
    resize, crop = transforms.Resize(256), transforms.CenterCrop(224)
    normalize = transforms.Compose([transforms.ToTensor(), transforms.Normalize(
        mean=[.485,.456,.406], std=[.229,.224,.225])])
    settings = dict(created_utc=datetime.now(timezone.utc).isoformat(), video_path=info['video_path'],
        video_sha256=info['video_sha256'], weight_sha256_checked_only=info['weight_sha256'],
        model_loaded=False, inference_started=False, automatic_tracking=False,
        candidates=CANDIDATES, official_preprocessing=dict(resize=repr(resize), crop=repr(crop),
        normalize=repr(normalize), color='OpenCV BGR to RGB/PIL'),
        official_source=info['official_source_sha256'], time_limits=info['time_limits'],
        manual_labels_modified=False, candidate_interval_s=[.750,1.400],
        source_padding_policy='Only C has explicit constant top padding; all others must be in bounds. No silent clipping.')
    for name,h in info['official_source_sha256'].items():
        assert digest(SOURCE/'sixdrepnet360'/name)==h
    for c in CANDIDATES:
        (OUT/c['id']/'model_girdileri').mkdir(parents=True,exist_ok=False)
    for name in ('karsilastirma','kaynak','son32_C'): (OUT/name).mkdir()
    cap = cv2.VideoCapture(info['video_path'])
    if not cap.isOpened(): raise RuntimeError('Video open failed')
    rows=[]; tiles=[]; late=[]; index=0
    def sheet(tiles,path,cols):
        w,h=tiles[0].size
        im=Image.new('RGB',(w*cols,h*math.ceil(len(tiles)/cols)),'#eeeeee')
        for j,tile in enumerate(tiles): im.paste(tile,((j%cols)*w,(j//cols)*h))
        im.save(path)
    try:
        fps=cap.get(cv2.CAP_PROP_FPS)
        assert fps==24
        while True:
            ok,frame=cap.read()
            if not ok: break
            height,width=frame.shape[:2]
            assert (width,height)==(1280,720)
            source=Image.fromarray(cv2.cvtColor(frame,cv2.COLOR_BGR2RGB))
            msec=float(cap.get(cv2.CAP_PROP_POS_MSEC)); pts=float(cap.get(cv2.CAP_PROP_PTS))
            tile=Image.new('RGB',(1016,284),'white'); d=ImageDraw.Draw(tile)
            d.text((6,3),f'Frame {index:03d} | nominal {index/fps:.6f}s | decoder {msec:.3f}ms | PTS ticks {pts}',fill='black')
            tile.paste(source.resize((320,180)),(4,42))
            for j,c in enumerate(CANDIDATES):
                x,y,w,h=(c[k] for k in ('x','y','width','height'))
                if c['padding']=='none':
                    if min(x,y)<0 or x+w>width or y+h>height: raise ValueError('Out-of-bounds unpadded ROI')
                    roi=source.crop((x,y,x+w,y+h)); padding=[0,0,0,0]
                else:
                    assert c['id']=='C_ust40_acik_dolgu' and y==-40 and x>=0 and x+w<=width and y+h<=height
                    roi=Image.new('RGB',(w,h),(128,128,128))
                    roi.paste(source.crop((x,0,x+w,y+h)),(0,40)); padding=[0,40,0,0]
                scaled=resize(roi); actual=crop(scaled)
                tensor=normalize(actual).unsqueeze(0)
                assert actual.size==(224,224) and tensor.shape==(1,3,224,224) and torch.isfinite(tensor).all()
                left=round((scaled.width-224)/2); top=round((scaled.height-224)/2)
                box=[x+left*w/scaled.width,y+top*h/scaled.height,
                     x+(left+224)*w/scaled.width,y+(top+224)*h/scaled.height]
                c['effective_source_box_after_centercrop']=box
                c['source_padding_ltrb']=padding
                rel=f"{c['id']}/model_girdileri/kare_{index:06d}.png"; actual.save(OUT/rel)
                tile.paste(actual,(328+j*228,42))
                d.text((328+j*228,23),c['id'],fill='black')
                rows.append(dict(frame_index=index,candidate=c['id'],nominal_time_s=index/fps,
                    decoder_pos_msec=msec,decoder_pts_ticks=pts,decoder_pts_time_s=pts/fps,
                    input_image=rel,input_rgb_sha256=hashlib.sha256(actual.tobytes()).hexdigest(),
                    normalized_tensor_sha256=hashlib.sha256(tensor.numpy().tobytes()).hexdigest(),
                    visual_review='pending',padding_top_source_px=padding[1]))
                if c['id'].startswith('C_') and index>=136:
                    lt=Image.new('RGB',(232,254),'white'); ld=ImageDraw.Draw(lt)
                    ld.text((4,3),f'Frame {index:03d} | {index/fps:.6f}s',fill='black');lt.paste(actual,(4,26));late.append(lt)
            d.text((6,266),'Native 224x224 inputs. C includes EXPLICIT synthetic top padding. NO MODEL INFERENCE.',fill='black')
            tiles.append(tile)
            if index in (0,36,72,136,137,138,167):
                context=source.copy(); cd=ImageDraw.Draw(context)
                for c,color in zip(CANDIDATES,('red','orange','cyan')):
                    box=c['effective_source_box_after_centercrop']; cd.rectangle(tuple(box),outline=color,width=2)
                context.save(OUT/'kaynak'/f'kare_{index:06d}.png')
            if len(tiles)==8:
                sheet(tiles,OUT/'karsilastirma'/f'sayfa_{index//8+1:03d}.png',2);tiles=[]
            index+=1
        assert index==168 and not tiles
        for k in (0,16): sheet(late[k:k+16],OUT/'son32_C'/f'sayfa_{k//16+1:03d}.png',4)
    finally: cap.release()
    settings.update(decoded_frame_count=index,fps=fps,input_count=len(rows),resolution=[1280,720],
        general_page_count=21,native_C_last32_pages=2,visual_review_completed=False)
    write_json('ayarlar.json',settings)
    with (OUT/'kareler.csv').open('w',encoding='utf-8',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)
    changed=[path for path,h in protected.items() if not Path(path).is_file() or digest(path)!=h]
    write_json('dosya_kontrolu.json',dict(protected_count=len(protected),changed=changed,
        all_source_and_prior_files_unchanged=not changed,all_504_inputs_224x224=True,model_inference_performed=False))
    assert not changed
    print(str(OUT),flush=True)
    print(f'Decoded {index}; real preprocessed inputs {len(rows)}; no inference; protected files {len(protected)} unchanged.',flush=True)

if __name__=='__main__': main()
