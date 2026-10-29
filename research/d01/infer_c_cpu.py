"""Explicitly padded C experiment; durable per-frame records; local CPU only."""
from pathlib import Path
import csv
import ctypes as ct
import hashlib
import importlib
import json
import math
import os
import signal
import subprocess
import sys
import time
import traceback
from datetime import datetime, timezone

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

def digest(path):
    h=hashlib.sha256()
    with Path(path).open('rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''): h.update(b)
    return h.hexdigest()

def atomic_json(path,value):
    tmp=path.with_suffix('.tmp')
    with tmp.open('w',encoding='utf-8') as f:
        json.dump(value,f,ensure_ascii=False,indent=2,allow_nan=False);f.write('\n');f.flush();os.fsync(f.fileno())
    os.replace(tmp,path)

def main():
    if (OUT/'report.json').exists() or (OUT/'kareler.jsonl').exists(): raise RuntimeError('Output already exists; no overwrite.')
    started=time.perf_counter(); rows=[]; matrices={}; memory=[]; protected={}; cap=None
    info=dict(run_status='running',pid=os.getpid(),started_utc=datetime.now(timezone.utc).isoformat(),
        device='cpu',requested_frames=168,completed_frames=0,valid_frames=0,failed_frames=[],
        smoothing=False,angle_unwrap=False,behavior_result=None,confidence=None,manual_labels_approved=False,
        padding_effect_validated=False,source_experiment=str(AUDIT),timing={})
    def mem(stage):
        try:
            from ctypes import wintypes as w
            class Counters(ct.Structure):
                _fields_=[('cb',w.DWORD),('PageFaultCount',w.DWORD)]+[(n,ct.c_size_t) for n in (
                    'PeakWorkingSetSize','WorkingSetSize','QuotaPeakPagedPoolUsage','QuotaPagedPoolUsage',
                    'QuotaPeakNonPagedPoolUsage','QuotaNonPagedPoolUsage','PagefileUsage','PeakPagefileUsage','PrivateUsage')]
            kernel=ct.WinDLL('kernel32',use_last_error=True);psapi=ct.WinDLL('psapi',use_last_error=True)
            kernel.GetCurrentProcess.restype=w.HANDLE
            psapi.GetProcessMemoryInfo.argtypes=[w.HANDLE,ct.POINTER(Counters),w.DWORD]
            psapi.GetProcessMemoryInfo.restype=w.BOOL
            c=Counters();c.cb=ct.sizeof(c)
            if not psapi.GetProcessMemoryInfo(kernel.GetCurrentProcess(),ct.byref(c),c.cb): raise OSError(ct.get_last_error())
            sample=dict(stage=stage,elapsed_s=time.perf_counter()-started,working_set_bytes=c.WorkingSetSize,
                peak_working_set_bytes=c.PeakWorkingSetSize,private_bytes=c.PrivateUsage)
            memory.append(sample);return sample
        except Exception as e: info['memory_error']=str(e);return None
    def checkpoint():
        info.update(completed_frames=len(rows),valid_frames=sum(r['valid'] for r in rows),
            failed_frames=[r['frame_index'] for r in rows if not r['valid']],
            elapsed_s=time.perf_counter()-started,last_update_utc=datetime.now(timezone.utc).isoformat(),memory_samples=memory)
        if memory: info['peak_process_working_set_bytes']=max(s['peak_working_set_bytes'] for s in memory)
        atomic_json(OUT/'report.json',info)
    def interrupt(signum,frame): raise KeyboardInterrupt(f'Signal {signum}')
    signal.signal(signal.SIGINT,interrupt)
    if hasattr(signal,'SIGBREAK'): signal.signal(signal.SIGBREAK,interrupt)
    checkpoint();mem('before_imports')
    try:
        assert sys.version_info >= (3, 11)  # Environment folder name is not part of the data contract
        prior=json.loads((ROOT/'outputs/d01_headpose_6drepnet360/run_20261011T202732_409166Z_c18fcc05/provenance.json').read_text(encoding='utf-8'))
        settings=json.loads((AUDIT/'ayarlar.json').read_text(encoding='utf-8'))
        roi=json.loads((AUDIT/'roi_oneri.json').read_text(encoding='utf-8'))
        if _ARGS.video: roi['video_path']=str(_ARGS.video.resolve())
        review=json.loads((AUDIT/'gorsel_inceleme.json').read_text(encoding='utf-8'))
        assert review['reviewed_frame_indices']==list(range(168)) and review['all_21_pages_reviewed']
        assert not review['candidates']['C_ust40_acik_dolgu']['head_cut_frames']
        assert [roi[k] for k in ('x','y','width','height')]==[250,-40,440,440]
        assert roi['fill_rgb']==[128,128,128] and roi['source_read_box']==[250,0,690,400]
        protected={str(p):digest(p) for p in (WEIGHTS,Path(roi['video_path']),MANUAL)}
        for base in (AUDIT,MANUAL.parent):
            protected.update({str(p.resolve()):digest(p) for p in base.rglob('*') if p.is_file()})
        atomic_json(OUT/'koruma_manifesti.json',protected)
        assert digest(WEIGHTS)==prior['model_sha256']==settings['weight_sha256_checked_only']
        assert digest(roi['video_path'])==roi['video_sha256']
        code_commit=subprocess.check_output(['git','-C',str(SOURCE),'rev-parse','HEAD'],text=True).strip()
        assert code_commit==prior['code_commit']
        for n,h in prior['official_source_sha256'].items(): assert digest(SOURCE/'sixdrepnet360'/n)==h
        info.update(roi=roi,video_sha256=roi['video_sha256'],weight_path=str(WEIGHTS),weight_sha256=digest(WEIGHTS),
            official_commit=code_commit,official_source_sha256=prior['official_source_sha256'],script_sha256=digest(__file__),
            manual_reference=dict(path=str(MANUAL),sha256=digest(MANUAL),marks=json.loads(MANUAL.read_text(encoding='utf-8-sig'))['marks']),
            manual_candidate_interval_s=[.750,1.400],manual_end_is_approximate=True,
            time_limits='Decoder times and nominal index/FPS are recorded separately; LibVLC/audio alignment not independently verified.',
            memory_scope='Local Python process Windows working set/OS peak, includes imports/model/preflight/plots; not server/system RAM.')
        t=time.perf_counter()
        import torch
        import torchvision
        import numpy as np
        import cv2
        from PIL import Image,ImageDraw
        from torchvision import transforms
        os.environ['MPLCONFIGDIR']=str(OUT/'matplotlib_config')
        import matplotlib
        matplotlib.use('Agg')
        import matplotlib.pyplot as plt
        info['timing']['imports_s']=time.perf_counter()-t
        info['packages']={n:importlib.metadata.version(n) for n in ('torch','torchvision','numpy','pillow','matplotlib')}
        torch.set_num_threads(min(4,os.cpu_count() or 1));info['cpu_threads']=torch.get_num_threads()
        from official_runtime import input_transforms, load_official_model
        resize,crop,norm=input_transforms()
        expected=[r for r in csv.DictReader((AUDIT/'kareler.csv').open(encoding='utf-8',newline='')) if r['candidate']=='C_ust40_acik_dolgu']
        assert [int(r['frame_index']) for r in expected]==list(range(168))
        t=time.perf_counter();cap=cv2.VideoCapture(roi['video_path'])
        assert cap.isOpened() and cap.get(cv2.CAP_PROP_FPS)==24
        checks=[]
        for e in expected:
            ok,frame=cap.read();assert ok and frame.shape==(720,1280,3)
            assert abs(cap.get(cv2.CAP_PROP_POS_MSEC)-float(e['decoder_pos_msec']))<1e-6
            assert cap.get(cv2.CAP_PROP_PTS)==float(e['decoder_pts_ticks'])
            source=Image.fromarray(cv2.cvtColor(frame,cv2.COLOR_BGR2RGB))
            canvas=Image.new('RGB',(440,440),(128,128,128));canvas.paste(source.crop((250,0,690,400)),(0,40))
            actual=crop(resize(canvas))
            with Image.open(AUDIT/e['input_image']) as saved:
                assert saved.mode=='RGB' and saved.size==(224,224)
                assert saved.tobytes()==actual.tobytes()
            rgb_hash=hashlib.sha256(actual.tobytes()).hexdigest();assert rgb_hash==e['input_rgb_sha256']
            tensor=norm(actual).unsqueeze(0)
            tensor_hash=hashlib.sha256(tensor.numpy().tobytes()).hexdigest();assert tensor_hash==e['normalized_tensor_sha256']
            checks.append(dict(frame_index=int(e['frame_index']),rgb_sha256=rgb_hash,tensor_sha256=tensor_hash,matched=True))
        assert not cap.read()[0];cap.release();cap=None
        atomic_json(OUT/'girdi_hash_kontrolu.json',checks)
        info['timing']['preflight_decode_preprocess_hash_s']=time.perf_counter()-t
        info['all_168_audited_input_hashes_match']=True
        checkpoint();print('168/168 rebuilt C RGB and normalized tensor hashes match; loading CPU model.',flush=True)
        sys.path.insert(0,str(SOURCE/'sixdrepnet360'))
        official=importlib.import_module('test');utils=importlib.import_module('utils')
        assert Path(official.__file__).resolve()==(SOURCE/'sixdrepnet360/test.py').resolve()
        t=time.perf_counter()
        model,utils,load_checks=load_official_model(SOURCE,WEIGHTS)
        info.update(load_checks)
        info['timing']['model_create_load_s']=time.perf_counter()-t;mem('model_loaded')
        red=norm(Image.new('RGB',(224,224),(255,0,0)))
        assert torch.allclose(red[:,0,0],torch.tensor([(1-.485)/.229,-.456/.224,-.406/.225]),atol=1e-6)
        assert torch.allclose(utils.compute_euler_angles_from_rotation_matrices(torch.eye(3).unsqueeze(0)),torch.zeros((1,3)),atol=1e-6)
        known=torch.tensor(utils.get_R(.2,-.3,.4),dtype=torch.float32).unsqueeze(0)
        assert torch.allclose(utils.compute_euler_angles_from_rotation_matrices(known),torch.tensor([[.2,-.3,.4]]),atol=1e-6)
        axis=np.zeros((120,120,3),dtype=np.uint8);utils.draw_axis(axis,0.,0.,0.,tdx=50,tdy=50,size=30)
        assert axis[50,78].tolist()==[0,0,255] and axis[78,50].tolist()==[0,255,0]
        def so3(a,b): return math.degrees(math.acos(float(np.clip((np.trace(a.T@b)-1)/2,-1,1))))
        assert so3(np.eye(3),np.eye(3))==0 and abs(so3(np.eye(3),utils.get_R(0,0,math.pi/2))-90)<1e-10
        info['checks']=dict(rgb_normalization=True,euler_identity=True,euler_known_rotation=True,zero_axis=True,so3_identity_and_90deg=True)
        info['convention']=dict(unit='degrees',matrix='right-handed Rz @ Ry @ Rx; official get_R',
            euler='pitch=X, yaw=Y, roll=Z; official compute_euler_angles_from_rotation_matrices; yaw branch [-90,90]',
            so3='acos(clip((trace(R_previous.T @ R_current)-1)/2,-1,1)), degrees; only adjacent valid frames',
            axes='official draw_axis negates yaw; X red, Y green, Z blue; fixed image centre, not anatomical centre')
        checkpoint();loop=time.perf_counter()
        with (OUT/'kareler.jsonl').open('x',encoding='utf-8') as log:
            for e in expected:
                i=int(e['frame_index']);row=dict(frame_index=i,nominal_time_s=float(e['nominal_time_s']),
                    decoder_pos_msec=float(e['decoder_pos_msec']),decoder_pts_ticks=float(e['decoder_pts_ticks']),
                    decoder_time_s=float(e['decoder_pts_time_s']),time_source='OpenCV FFmpeg CAP_PROP_PTS / FPS; audit decoder time',
                    input_rgb_sha256=None,normalized_tensor_sha256=None,rotation_matrix=None,pitch_deg=None,yaw_deg=None,roll_deg=None,
                    inference_s=None,valid=False,attempted=False,so3_from_previous_deg=None,error=None)
                try:
                    with Image.open(AUDIT/e['input_image']) as image: image=image.copy()
                    row['input_rgb_sha256']=hashlib.sha256(image.tobytes()).hexdigest();assert row['input_rgb_sha256']==e['input_rgb_sha256']
                    tensor=norm(image).unsqueeze(0).cpu()
                    row['normalized_tensor_sha256']=hashlib.sha256(tensor.numpy().tobytes()).hexdigest()
                    assert row['normalized_tensor_sha256']==e['normalized_tensor_sha256']
                    assert tensor.shape==(1,3,224,224) and torch.isfinite(tensor).all()
                    row['attempted']=True;t=time.perf_counter()
                    try:
                        with torch.inference_mode(): rotation=model(tensor)
                    finally: row['inference_s']=time.perf_counter()-t
                    assert rotation.shape==(1,3,3) and torch.isfinite(rotation).all()
                    R=rotation[0].cpu().numpy().astype(np.float64);row['rotation_matrix']=R.tolist()
                    row['determinant']=float(np.linalg.det(R));row['max_orthogonality_error']=float(np.max(np.abs(R.T@R-np.eye(3))))
                    assert abs(row['determinant']-1)<=1e-4 and row['max_orthogonality_error']<=1e-4
                    angles=utils.compute_euler_angles_from_rotation_matrices(rotation)[0]*180/math.pi
                    p,y,r=[float(v) for v in angles];assert all(math.isfinite(v) for v in (p,y,r))
                    row.update(pitch_deg=p,yaw_deg=y,roll_deg=r,valid=True);matrices[i]=R
                    if i-1 in matrices: row['so3_from_previous_deg']=so3(matrices[i-1],R)
                except Exception as exc: row['error']=f'{type(exc).__name__}: {exc}'
                row['memory']=mem(f'frame_{i}')
                log.write(json.dumps(row,ensure_ascii=False,allow_nan=False)+'\n');log.flush();os.fsync(log.fileno())
                rows.append(row);checkpoint()
                if (i+1)%12==0: print(f'Persisted {i+1}/168; valid {info["valid_frames"]}',flush=True)
        info['timing']['frame_loop_s']=time.perf_counter()-loop
        info['timing']['forward_sum_s']=sum(r['inference_s'] for r in rows if r['inference_s'] is not None)
        info['timing']['note']='Local CPU batch=1, 4 or fewer threads, no warmup/retry. Forward sum is inside frame loop; totals overlap. Loop includes durable writes.'
        checkpoint()
        with (OUT/'acilar.csv').open('w',encoding='utf-8',newline='') as f:
            fields=['frame_index','decoder_time_s','time_source','nominal_time_s','pitch_deg','yaw_deg','roll_deg','so3_from_previous_deg','inference_s','valid','error']
            w=csv.DictWriter(f,fieldnames=fields,extrasaction='ignore');w.writeheader();w.writerows(rows)
        info['largest_matrix_changes']=sorted([dict(frame_from=r['frame_index']-1,frame_to=r['frame_index'],so3_deg=r['so3_from_previous_deg']) for r in rows if r['so3_from_previous_deg'] is not None],key=lambda r:r['so3_deg'],reverse=True)[:15]
        info['largest_euler_changes']=sorted([dict(frame_from=a['frame_index'],frame_to=b['frame_index'],
            component_deltas_deg={k:b[k]-a[k] for k in ('pitch_deg','yaw_deg','roll_deg')},max_abs_component_deg=max(abs(b[k]-a[k]) for k in ('pitch_deg','yaw_deg','roll_deg')),so3_deg=b['so3_from_previous_deg'])
            for a,b in zip(rows,rows[1:]) if a['valid'] and b['valid']],key=lambda r:r['max_abs_component_deg'],reverse=True)[:15]
        def save(fig,name):
            fig.tight_layout();fig.savefig(OUT/(name+'.png'),dpi=150);fig.savefig(OUT/(name+'.svg'));plt.close(fig)
        def decorate(ax):
            ax.axvspan(.750,1.400,color='orange',alpha=.18,label='Manual candidate 0.750 to approx 1.400 s; alignment unverified');ax.grid(alpha=.3)
        t=[r['decoder_time_s'] for r in rows]
        fig,axs=plt.subplots(3,1,figsize=(14,9),sharex=True)
        for ax,k in zip(axs,('pitch_deg','yaw_deg','roll_deg')):
            ax.plot(t,[r[k] if r['valid'] else np.nan for r in rows],'.-',markersize=3);ax.set_ylabel(k+' (degrees)');decorate(ax)
        axs[0].legend(fontsize=9);axs[-1].set_xlabel('Decoder presentation time (s); LibVLC/audio alignment unverified')
        fig.suptitle('C padded ROI / raw Euler; no smoothing, no unwrap');save(fig,'ham_acilar')
        fig,ax=plt.subplots(figsize=(14,5));ax.plot(t,[r['so3_from_previous_deg'] if r['so3_from_previous_deg'] is not None else np.nan for r in rows],'.-')
        decorate(ax);ax.legend(fontsize=9);ax.set_ylabel('Adjacent SO(3) angle (degrees)');ax.set_xlabel('Decoder presentation time (s); no behavioral threshold');save(fig,'ardisik_so3')
        fig,axs=plt.subplots(4,3,figsize=(17,11))
        for col,(lo,hi,title) in enumerate(((30,42,'Frame 36'),(66,78,'Frame 72'),(136,167,'Late frames 136-167'))):
            rs=rows[lo:hi+1]
            for ax,k in zip(axs[:,col],('pitch_deg','yaw_deg','roll_deg','so3_from_previous_deg')):
                ax.plot([r['frame_index'] for r in rs],[r[k] if r[k] is not None else np.nan for r in rs],'.-');ax.grid(alpha=.3);ax.set_ylabel(k+' (deg)')
                if col<2: ax.axvline((36,72)[col],color='red',linestyle='--')
            axs[0,col].set_title(title);axs[-1,col].set_xlabel('0-based frame index')
        fig.suptitle('Raw Euler vs true matrix differences; no smoothing');save(fig,'36_72_136_167_inceleme')
        (OUT/'eksenler').mkdir()
        for group,indices in [('036',range(33,40)),('072',range(69,76)),('son32_1',range(136,152)),('son32_2',range(152,168))]:
            tiles=[]
            for i in indices:
                row=rows[i];image=cv2.imread(str(AUDIT/expected[i]['input_image']))
                if row['valid']: utils.draw_axis(image,row['yaw_deg'],row['pitch_deg'],row['roll_deg'],tdx=112,tdy=112,size=55)
                cv2.imwrite(str(OUT/'eksenler'/f'kare_{i:06d}.png'),image)
                tile=Image.new('RGB',(240,285),'white');d=ImageDraw.Draw(tile)
                d.text((4,4),f"Frame {i} / t={row['decoder_time_s']:.4f}s",fill='black')
                d.text((4,21),f"P {row['pitch_deg']:.1f} Y {row['yaw_deg']:.1f} R {row['roll_deg']:.1f}" if row['valid'] else 'INVALID',fill='black')
                tile.paste(Image.fromarray(cv2.cvtColor(image,cv2.COLOR_BGR2RGB)),(8,52));tiles.append(tile)
            cols=4;sheet=Image.new('RGB',(cols*240,math.ceil(len(tiles)/cols)*285),'#eeeeee')
            for pos,tile in enumerate(tiles):sheet.paste(tile,((pos%cols)*240,(pos//cols)*285))
            sheet.save(OUT/f'eksen_{group}.png')
        mem('plots_written');info['run_status']='completed' if all(r['valid'] for r in rows) else 'failed'
    except KeyboardInterrupt:
        info['run_status']='interrupted';info['interruption']='KeyboardInterrupt/SIGINT/SIGBREAK; durable completed rows retained'
        print('Interrupted; completed rows preserved.',flush=True)
    except Exception:
        info['run_status']='failed';info['fatal_error']=traceback.format_exc();print(info['fatal_error'],flush=True)
    finally:
        if cap is not None: cap.release()
        changed=[p for p,h in protected.items() if not Path(p).is_file() or digest(p)!=h]
        info['protected_files_checked']=len(protected);info['protected_files_changed']=changed
        if changed: info['run_status']='failed'
        info['timing']['end_to_end_s']=time.perf_counter()-started
        info['finished_utc']=datetime.now(timezone.utc).isoformat();checkpoint()
    print(f"{OUT}: {info['run_status']}; {info['completed_frames']} completed / {info['valid_frames']} valid / {len(info['failed_frames'])} invalid",flush=True)
    return 0 if info['run_status']=='completed' else 1

if __name__=='__main__': raise SystemExit(main())
