"""Post-process recorded rotation matrices only. No model import/load/forward."""
from pathlib import Path
import csv,hashlib,json,math,os,sys
from datetime import datetime,timezone
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
RAW = (_ARGS.raw_dir or ROOT/'outputs/d01_headpose_6drepnet360/c_cpu_20261029T080111Z').resolve()
MANUAL = MANUAL.parent
import shutil
shutil.copyfile(Path(__file__).resolve().parent/'parameters/smoothing.json', OUT/'parametreler.json')

def sha(p):
    h=hashlib.sha256()
    with Path(p).open('rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
    return h.hexdigest()
def js(name,data): (OUT/name).write_text(json.dumps(data,ensure_ascii=False,indent=2,allow_nan=False)+'\n',encoding='utf-8')
def main():
    if (OUT/'report.json').exists():raise RuntimeError('No overwrite')
    manifest={str(p.resolve()):sha(p) for base in (RAW,AUDIT,MANUAL) for p in base.rglob('*') if p.is_file()}
    js('koruma_manifesti.json',manifest)
    params=json.loads((OUT/'parametreler.json').read_text(encoding='utf-8'))
    report=json.loads((RAW/'report.json').read_text(encoding='utf-8'))
    assert report['run_status']=='completed'
    source=SOURCE/'sixdrepnet360'
    assert sha(source/'utils.py')==report['official_source_sha256']['utils.py']
    import numpy as np
    import torch
    import cv2
    from scipy.spatial.transform import Rotation
    from PIL import Image,ImageDraw
    os.environ['MPLCONFIGDIR']=str(OUT/'matplotlib_config')
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    sys.path.insert(0,str(source));import utils
    rows=[json.loads(s) for s in (RAW/'kareler.jsonl').read_text(encoding='utf-8').splitlines()]
    assert len(rows)==168 and all(r['valid'] for r in rows)
    R=np.array([r['rotation_matrix'] for r in rows]);t=np.array([r['decoder_time_s'] for r in rows])
    stored=np.array([[r[k] for k in ('pitch_deg','yaw_deg','roll_deg')] for r in rows])
    def euler(mats):return (utils.compute_euler_angles_from_rotation_matrices(torch.tensor(mats,dtype=torch.float32))*180/math.pi).numpy().astype(float)
    E=euler(R);assert np.max(abs(E-stored))<1e-5
    # Official extraction is Rz @ Ry @ Rx; official drawing projects D R.T D, D=diag(1,-1,1).
    D=np.diag([1.,-1.,1.]);reconstruction=[];projection=[];raster=[]
    for i,(r,e) in enumerate(zip(R,E)):
        reconstructed=utils.get_R(*np.radians(e));reconstruction.append(float(np.max(abs(reconstructed-r))))
        p,y,z=np.radians(e);y=-y
        official_projection=np.array([[math.cos(y)*math.cos(z),-math.cos(y)*math.sin(z),math.sin(y)],
            [math.cos(p)*math.sin(z)+math.cos(z)*math.sin(p)*math.sin(y),
             math.cos(p)*math.cos(z)-math.sin(p)*math.sin(y)*math.sin(z),-math.cos(y)*math.sin(p)]])
        projection.append(float(np.max(abs(official_projection-(D@r.T@D)[:2]))))
        a=np.zeros((224,224,3),np.uint8);b=a.copy()
        utils.draw_axis(a,e[1],e[0],e[2],tdx=112,tdy=112,size=55)
        utils.draw_axis(b,stored[i,1],stored[i,0],stored[i,2],tdx=112,tdy=112,size=55)
        raster.append(bool(np.array_equal(a,b)))
    assert max(reconstruction)<2e-6 and max(projection)<2e-6 and all(raster)
    def polar(m):
        u,s,vt=np.linalg.svd(m);return u@np.diag([1,1,np.linalg.det(u@vt)])@vt
    P=np.array([polar(r) for r in R])
    def delta(a,b):return float(np.degrees(Rotation.from_matrix(a.T@b).magnitude()))
    def filters(mats):
        out={'raw':mats.copy()}
        for name,alpha in [('ema_050',.5),('ema_025',.25)]:
            filtered=[mats[0]]
            for target in mats[1:]:
                rel=Rotation.from_matrix(filtered[-1].T@target).as_rotvec()
                filtered.append(filtered[-1]@Rotation.from_rotvec(alpha*rel).as_matrix())
            out[name]=np.array(filtered)
        out['centered_5']=np.array([polar(np.mean(mats[max(0,i-2):min(len(mats),i+3)],axis=0)) for i in range(len(mats))])
        return out
    F=filters(P);F['raw']=R.copy() # immutable original matrices remain the raw reference, no silent replacement
    angles={k:euler(v) for k,v in F.items()}
    adjacent={k:np.array([np.nan]+[delta(a,b) for a,b in zip(v,v[1:])]) for k,v in F.items()}
    distance={k:np.array([delta(polar(a),polar(b)) for a,b in zip(R,v)]) for k,v in F.items()}
    # Preserve complete matrices and derived results; no altered raw records.
    derived=[]
    for method,mats in F.items():
        for i,(m,e) in enumerate(zip(mats,angles[method])):
            assert np.max(abs(m.T@m-np.eye(3)))<1e-4 and abs(np.linalg.det(m)-1)<1e-4
            derived.append(dict(method=method,frame_index=i,decoder_time_s=float(t[i]),time_source=rows[i]['time_source'],
                rotation_matrix=m.tolist(),pitch_deg=float(e[0]),yaw_deg=float(e[1]),roll_deg=float(e[2]),
                adjacent_so3_deg=None if i==0 else float(adjacent[method][i]),distance_to_raw_deg=float(distance[method][i]),valid=True))
    with (OUT/'turetilmis_sonuclar.jsonl').open('x',encoding='utf-8') as f:
        for r in derived:f.write(json.dumps(r,ensure_ascii=False,allow_nan=False)+'\n')
    with (OUT/'acilar_ve_farklar.csv').open('w',encoding='utf-8',newline='') as f:
        keys=[k for k in derived[0] if k!='rotation_matrix'];w=csv.DictWriter(f,fieldnames=keys,extrasaction='ignore');w.writeheader();w.writerows(derived)
    colors={'raw':'black','ema_050':'tab:blue','ema_025':'tab:green','centered_5':'tab:orange'}
    def save(fig,name):fig.tight_layout();fig.savefig(OUT/(name+'.png'),dpi=150);fig.savefig(OUT/(name+'.svg'));plt.close(fig)
    def band(ax):ax.axvspan(.75,1.4,color='gold',alpha=.12,label='Manual candidate only; alignment unverified');ax.grid(alpha=.3)
    for name,lo,hi in [('tum_klip',0,167),('aday_ve_sonrasi',12,43)]:
        sl=slice(lo,hi+1)
        fig,axs=plt.subplots(3,1,figsize=(15,10),sharex=True)
        for j,ax in enumerate(axs):
            for method in F:ax.plot(t[sl],angles[method][sl,j],'.-',markersize=2,color=colors[method],label=method)
            ax.set_ylabel(('pitch','yaw','roll')[j]+' (degrees)');band(ax)
        axs[0].legend(fontsize=8,ncol=2);axs[-1].set_xlabel('Decoder time (s); LibVLC alignment unverified')
        fig.suptitle('Raw official Euler representations; NO Euler averaging or unwrap');save(fig,'euler_'+name)
        fig,axs=plt.subplots(2,1,figsize=(15,9),sharex=True)
        for method in F:
            axs[0].plot(t[sl],adjacent[method][sl],'.-',markersize=3,color=colors[method],label=method)
            if method!='raw':axs[1].plot(t[sl],distance[method][sl],'.-',markersize=3,color=colors[method],label=method)
        for ax in axs:band(ax);ax.legend(fontsize=8)
        axs[0].set_ylabel('Adjacent predicted SO(3) difference (degrees)');axs[1].set_ylabel('Distance to RAW prediction (degrees)')
        axs[1].set_xlabel('Decoder time (s); raw is NOT ground truth');save(fig,'so3_'+name)
    # Side-by-side native 224px crops, no visual retouching. All methods use the same official draw_axis.
    (OUT/'eksenler').mkdir()
    selected=list(range(18,43))+[72,136,167]
    for n in range(0,len(selected),4):
        ids=selected[n:n+4];sheet=Image.new('RGB',(4*240,len(ids)*280),'#eeeeee')
        for pos,i in enumerate(ids):
            src=AUDIT/'C_ust40_acik_dolgu/model_girdileri'/f'kare_{i:06d}.png'
            image=cv2.imread(str(src));assert image is not None
            assert hashlib.sha256(Image.open(src).tobytes()).hexdigest()==rows[i]['input_rgb_sha256']
            for col,method in enumerate(F):
                pic=image.copy();e=angles[method][i];utils.draw_axis(pic,e[1],e[0],e[2],tdx=112,tdy=112,size=55)
                tile=Image.new('RGB',(240,280),'white');d=ImageDraw.Draw(tile)
                d.text((4,3),f'{method} | frame {i} | {t[i]:.4f}s',fill='black')
                d.text((4,20),f'P {e[0]:.1f} Y {e[1]:.1f} R {e[2]:.1f}',fill='black')
                tile.paste(Image.fromarray(cv2.cvtColor(pic,cv2.COLOR_BGR2RGB)),(8,48));sheet.paste(tile,(col*240,pos*280))
        sheet.save(OUT/'eksenler'/f'sayfa_{n//4+1:03d}.png')
    # Fixed synthetic controls; not derived from the manual candidate interval.
    step=np.array([Rotation.from_euler('z',0 if i<10 else 60,degrees=True).as_matrix() for i in range(40)])
    ramp=np.array([Rotation.from_euler('z',2*i,degrees=True).as_matrix() for i in range(40)])
    S=filters(step);G=filters(ramp)
    fig,axs=plt.subplots(2,1,figsize=(13,8))
    synthetic={}
    for method in F:
        sz=Rotation.from_matrix(S[method]).as_euler('xyz',degrees=True)[:,2]
        gz=Rotation.from_matrix(G[method]).as_euler('xyz',degrees=True)[:,2]
        axs[0].plot(np.arange(40)/24,sz,'.-',color=colors[method],label=method)
        axs[1].plot(np.arange(40)/24,gz,'.-',color=colors[method],label=method)
        synthetic[method]=dict(step_degrees_frames_8_to_14=sz[8:15].tolist(),
            ramp_last_interior_frame_35_error_deg=float(70-gz[35]))
    for ax in axs:ax.grid(alpha=.3);ax.legend();ax.set_ylabel('Z angle (degrees)');ax.set_xlabel('Synthetic time (s) at 24 FPS')
    axs[0].set_title('Fixed 60-degree step: anticipation vs causal lag (not this video)')
    axs[1].set_title('Fixed 2-degree/frame ramp (not this video)');save(fig,'sentetik_gecikme_kontrolu')
    metrics={}
    for method in F:
        metrics[method]=dict(max_adjacent_deg=float(np.nanmax(adjacent[method])),
            max_adjacent_frame_to=int(np.nanargmax(adjacent[method])),median_adjacent_deg=float(np.nanmedian(adjacent[method])),
            max_distance_to_raw_deg=float(max(distance[method])),mean_distance_to_raw_deg=float(np.mean(distance[method])),
            selected_transitions={str(i-1)+'_'+str(i):float(adjacent[method][i]) for i in (28,29,30,36,37,72,105)})
    checks=dict(official_utils_sha256=sha(source/'utils.py'),max_stored_vs_official_euler_difference_deg=float(np.max(abs(E-stored))),
        max_Euler_reconstruction_matrix_element_error=max(reconstruction),
        max_official_axis_projection_vs_D_R_transpose_D_error=max(projection),all_168_official_axis_rasters_identical_to_original=True,
        D_diagonal=[1,-1,1],convention_fix_required=False,
        filter_input_explicit_SVD_roundoff_projection_max_frobenius=float(np.max(np.linalg.norm(P-R,axis=(1,2)))),
        raw_matrices_changed=False)
    changed=[p for p,h in manifest.items() if not Path(p).is_file() or sha(p)!=h];assert not changed
    js('report.json',dict(status='completed',created_utc=datetime.now(timezone.utc).isoformat(),
        source_raw_sha256=sha(RAW/'kareler.jsonl'),parameters_sha256=sha(OUT/'parametreler.json'),
        parameters=params,convention_checks=checks,metrics=metrics,synthetic=synthetic,
        protected_count=len(manifest),protected_changed=changed,source_frames=168,methods=4,
        future_use='centered_5 uses two future frames (83.333ms at 24 FPS) except truncated clip ends; offline',
        behavior_result=None,pose_accuracy_reference=False,manual_labels_approved=False,no_model_inference=True))
    print(json.dumps(dict(checks=checks,metrics=metrics,synthetic=synthetic,protected_count=len(manifest)),indent=2),flush=True)
if __name__=='__main__':main()
