import csv
import hashlib
import html
import importlib.metadata
import json
import shutil
import subprocess
import time
from pathlib import Path

import cv2
import numpy as np

from .events import evaluate
from .vision import FaceTrack,head_pose,add_pose_change,pixels


def json_write(path,data):
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2,allow_nan=False),encoding="utf-8")


def resolve_video(config,override,root):
    if override:
        p=Path(override).expanduser().resolve()
        if not p.is_file():
            raise ValueError("Video bulunamadı: "+str(p))
        return p
    p=Path(config["video"])
    if p.is_file():
        return p.resolve()
    # The displayed ellipsis may be a UI abbreviation rather than a filename.
    if p.parent.is_dir():
        matches=list(p.parent.glob("Toddler_turns_toward_caregiver*.mp4"))
        if len(matches)==1:
            return matches[0].resolve()
        if len(matches)>1:
            raise ValueError("Birden fazla aday video var. --video ile tam dosyayı belirtin.")
    included=root/"sample"/"source.mp4"
    if included.is_file():
        print("Verilen Windows yolu bulunamadı. Paketteki aynı video kopyası kullanılıyor.",flush=True)
        return included
    raise ValueError("Video bulunamadı. --video ile gerçek yolu belirtin; … karakteri dosya adında olmayabilir.")


def validate(config,width,height,duration,source):
    if config.get("expected_size")!=[width,height] or abs(config.get("expected_duration_s",duration)-duration)>.15:
        raise ValueError("Video bu sahne ayarıyla eşleşmiyor. Yeni video için bölgeleri yeniden tanımlayın.")
    checksum=hashlib.sha256(source.read_bytes()).hexdigest()
    if config.get("expected_sha256") and checksum!=config["expected_sha256"]:
        raise ValueError("Video içeriği bu ayarla eşleşmiyor (SHA256). Yeni video için yeni ayar oluşturun.")
    ids=[t["id"] for t in config["targets"]]
    if len(set(ids))!=len(ids):
        raise ValueError("Hedef kimlikleri tekil olmalı.")
    for box in [config["child_head"],config["adult_head"],config["child_search_region"],config["adult_search_region"]]+[t["bbox"] for t in config["targets"]]:
        if len(box)!=4 or not all(0<=float(x)<=1 for x in box) or box[0]>=box[2] or box[1]>=box[3]:
            raise ValueError("Geçersiz normalize bölge: "+repr(box))
    for c in config["calls"]:
        if not 0<=c["start_s"]<c["end_s"]<=duration:
            raise ValueError("Çağrı zamanları video sınırları içinde olmalı.")
        if c.get("speaker_target_id") is not None and c["speaker_target_id"] not in ids:
            raise ValueError("Konuşan kişi hedef kimliği bulunamadı.")
    s=config["settings"]
    for key in ["gaze_fps","cpu_threads","baseline_s","observation_s","movement_hold_s","target_hold_s"]:
        if s[key]<=0:
            raise ValueError(key+" pozitif olmalı.")
    return checksum


def run(config,source,output,gaze_enabled=True):
    output=Path(output).resolve()
    if output.exists() and any(output.iterdir()):
        raise ValueError("Çıktı klasörü dolu. Yeni --output seçin; mevcut sonuçların üzerine yazılmadı.")
    cap=cv2.VideoCapture(str(source))
    if not cap.isOpened():
        raise ValueError("Video açılamadı.")
    fps=float(cap.get(cv2.CAP_PROP_FPS))
    count=int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    w,h=int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)),int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    if not np.isfinite(fps) or fps<=0 or count<=0:
        raise ValueError("Video zamanlama bilgisi geçersiz.")
    duration=count/fps
    checksum=validate(config,w,h,duration,source)
    output.mkdir(parents=True,exist_ok=True)
    s=config["settings"]
    print("Video: {} | {}x{} | {:.3f} FPS | {} kare".format(source,w,h,fps,count),flush=True)
    gaze=None
    if gaze_enabled:
        from .gaze import GazeEstimator
        print("Gaze-LLE yükleniyor (ilk çalıştırmada model indirilir)...",flush=True)
        gaze=GazeEstimator(s)
    child=FaceTrack(config["child_head"],config["child_search_region"],s["max_flow_gap_s"])
    adult=FaceTrack(config["adult_head"],config["adult_search_region"],s["max_flow_gap_s"])
    rows=[];gazerows=[];heatmaps=[];heat_times=[];next_gaze=0.;i=0
    start_clock=time.perf_counter()
    try:
        while True:
            ok,frame=cap.read()
            if not ok:
                break
            pts=float(cap.get(cv2.CAP_PROP_POS_MSEC))/1000
            t=pts if i==0 or pts>rows[-1]["time_s"] else i/fps
            if i and abs((t-rows[-1]["time_s"])-1/fps)>0.01:
                raise ValueError("Değişken FPS veya tutarsız PTS bulundu. Önce videoyu sabit FPS'e dönüştürün.")
            c=child.update(frame,t);a=adult.update(frame,t)
            row={"frame":i,"time_s":round(t,6),"child_bbox":c["bbox"],"child_track":c["source"],"adult_bbox":a["bbox"],"adult_track":a["source"],"pose_change_deg":None}
            row.update(head_pose(c["landmarks"],w,h,s["max_pose_reprojection_px"]))
            targets=[]
            for target in config["targets"]:
                target=dict(target)
                if target.get("track")=="adult":
                    if a["source"]=="lost":
                        continue
                    target["bbox"]=a["bbox"]
                targets.append(target)
            if t+1e-7>=next_gaze:
                if gaze is not None and c["source"]!="lost":
                    g,heat=gaze.predict(frame,c["bbox"],targets)
                    heatmaps.append(heat.astype(np.float16));heat_times.append(t)
                else:
                    g={"target":"unavailable","reason":"gaze_disabled" if gaze is None else "child_tracking_lost"}
                g.update({"frame":i,"time_s":round(t,6),"head_source":c["source"],"target_regions":targets})
                gazerows.append(g)
                next_gaze=t+1/s["gaze_fps"]
            rows.append(row)
            i+=1
            if i%24==0:
                print("Ölçüm: {}/{} kare, {:.1f} sn işlem".format(i,count,time.perf_counter()-start_clock),flush=True)
    finally:
        cap.release();child.close();adult.close()
    if len(rows)!=count:
        raise ValueError("Video eksik okundu: {}/{} kare".format(len(rows),count))
    events=[]
    # Each call gets its own baseline; global table contains the first call's change.
    for ci,call in enumerate(config["calls"]):
        eventrows=[dict(r,pose_change_deg=None) for r in rows]
        add_pose_change(eventrows,call,s)
        events.append(evaluate(call,eventrows,gazerows,s,fps,duration))
        json_write(output/("measurements_"+call["id"]+".json"),eventrows)
        if ci==0:
            rows=eventrows
    packages={}
    for name in ("numpy","mediapipe","torch","torchvision","timm"):
        packages[name]=importlib.metadata.version(name)
    result={"schema_version":1,"video":{"source":str(source),"sha256":checksum,"width":w,"height":h,"fps":fps,"frame_count":len(rows),"duration_s":duration,"time_base":"decoded presentation timestamps; fixed FPS required"},
            "configuration":config,"runtime":packages,"gaze_enabled":gaze_enabled,
            "events":events,"processing_seconds":round(time.perf_counter()-start_clock,2),
            "limitations":["Sahne bölgeleri elle tanımlı; oyuncak ve yetişkin gövdesi sabit bölgelerdir.","Baş pozu genel yüz ve yaklaşık kamera modeli kullanır.","Gaze-LLE sentetik çocuk videosu için doğrulanmış değildir.","Konuşan kişi otomatik bulunmadı; ses zamanları verilen kayıttan alındı.","Skorlar davranış olasılığı değildir; eşikler ilk prototip parametreleridir."]}
    json_write(output/"result.json",result)
    json_write(output/"frames.json",rows)
    json_write(output/"gaze.json",gazerows)
    json_write(output/"config_used.json",config)
    if heatmaps:
        np.savez_compressed(output/"heatmaps.npz",time_s=np.array(heat_times),heatmap=np.stack(heatmaps))
    fields=["frame","time_s","child_track","adult_track","pitch_deg","yaw_deg","roll_deg","pose_reprojection_px","pose_change_deg","target","gaze_sample_time_s","in_frame_score","heatmap_peak","target_margin","heatmap_spread"]
    gmap={g["frame"]:g for g in gazerows}
    with (output/"measurements.csv").open("w",encoding="utf-8-sig",newline="") as f:
        writer=csv.DictWriter(f,fieldnames=fields);writer.writeheader()
        for row in rows:
            d={key:row.get(key) for key in fields}
            if row["frame"] in gmap:
                g=gmap[row["frame"]];d.update({key:g.get(key) for key in fields if key in g and key not in ("time_s","frame")});d["gaze_sample_time_s"]=g["time_s"]
            writer.writerow(d)
    render_video(source,output,rows,gazerows,config,fps,w,h)
    make_report(output,result,rows,gazerows)
    print("Tamamlandı: "+str(output/"report.html"),flush=True)
    return result


def ffmpeg_executable():
    exe=shutil.which("ffmpeg")
    if exe:
        return exe
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except ImportError:
        raise RuntimeError("Sesli MP4 için ffmpeg veya imageio-ffmpeg kurulmalı.")


def render_video(source,output,rows,gazerows,config,fps,w,h):
    raw=output/"_silent_temp.mp4"
    cap=cv2.VideoCapture(str(source))
    writer=cv2.VideoWriter(str(raw),cv2.VideoWriter_fourcc(*"mp4v"),fps,(w,h))
    if not writer.isOpened():
        raise RuntimeError("MP4 video yazıcısı açılamadı.")
    gi=0
    colors={"adult_face":(90,220,80),"adult_body":(80,180,90),"toy":(0,180,255)}
    try:
        for row in rows:
            ok,frame=cap.read()
            if not ok:
                raise RuntimeError("İşaretli video oluşturulurken kare okunamadı.")
            t=row["time_s"]
            while gi+1<len(gazerows) and gazerows[gi+1]["time_s"]<=t+1e-7:
                gi+=1
            g=gazerows[gi] if gazerows and 0<=t-gazerows[gi]["time_s"]<1.5/config["settings"]["gaze_fps"] else {"target":"unavailable"}
            for target in g.get("target_regions",[]):
                x1,y1,x2,y2=pixels(target["bbox"],w,h);color=colors.get(target["id"],(255,180,0))
                cv2.rectangle(frame,(x1,y1),(x2,y2),color,2)
                cv2.putText(frame,target["id"],(x1,max(20,y1-7)),cv2.FONT_HERSHEY_SIMPLEX,.55,color,2)
            x1,y1,x2,y2=pixels(row["child_bbox"],w,h)
            cv2.rectangle(frame,(x1,y1),(x2,y2),(255,180,0) if row["child_track"]!="lost" else (0,0,255),2)
            if row.get("head_axis_px"):
                p,q=np.array(row["head_axis_px"],dtype=int)
                cv2.arrowedLine(frame,tuple(p),tuple(q),(255,160,30),2,tipLength=.15)
            if g.get("gaze_point"):
                gx,gy=int(g["gaze_point"][0]*w),int(g["gaze_point"][1]*h)
                cv2.circle(frame,(gx,gy),10,(255,0,255),2)
                cv2.line(frame,((x1+x2)//2,(y1+y2)//2),(gx,gy),(255,0,255),1)
            cv2.rectangle(frame,(0,0),(w,99),(23,25,32),-1)
            call_active=any(c["start_s"]<=t<=c["end_s"] for c in config["calls"])
            cv2.putText(frame,"t={:.2f}s | CALL: {} | child: {} | gaze: {}".format(t,"Deniz" if call_active else "-",row["child_track"],g["target"]),(18,28),cv2.FONT_HERSHEY_SIMPLEX,.64,(230,235,240),1)
            change=row.get("pose_change_deg")
            cv2.putText(frame,"Head change: {} | gaze sample: {}s | scores NOT calibrated confidence".format("{:.1f} deg".format(change) if change is not None else "missing",g.get("time_s","-")),(18,58),cv2.FONT_HERSHEY_SIMPLEX,.56,(230,235,240),1)
            cv2.putText(frame,"Blue: approximate head axis. Magenta: model target estimate. Speaker unresolved.",(18,86),cv2.FONT_HERSHEY_SIMPLEX,.52,(170,205,240),1)
            writer.write(frame)
    finally:
        cap.release();writer.release()
    exe=ffmpeg_executable()
    subprocess.run([exe,"-y","-v","error","-i",str(raw),"-i",str(source),"-map","0:v:0","-map","1:a:0?","-c:v","libx264","-pix_fmt","yuv420p","-crf","20","-c:a","aac","-movflags","+faststart",str(output/"annotated.mp4")],check=True)
    raw.unlink()


def make_report(output,result,rows,gazerows):
    esc=html.escape
    chunks=[]
    for event in result["events"]:
        chunks.append("<article><h2>{}</h2><p>{}</p><dl>".format(esc(event["call"]["name"]),esc(event["label_tr"])))
        for title,value in [("Çağrı aralığı",str(event["call"]["start_s"])+"–"+str(event["call"]["end_s"])+" sn"),("İlk genel baş pozu sapması (dönüş başlangıcı değildir)",event.get("first_pose_deviation")),("Hedef geçişiyle ilişkilendirilebilir baş değişimi",event["movement"]),("Yetişkin hedef dizisi",event["adult_target_run"]),("Hedef gecikmesi (çağrı başlangıcına göre, sn)",event["target_latency_from_start_s"]),("Baş hareketi gecikmesi (çağrı başlangıcına göre)",event["movement_latency_from_start_s"]),("Ölçüm kalitesi",event["measurement_quality"]),("Karar güveni",event["decision_confidence"]),("Baş pozu kapsaması",event["pose_coverage"]),("Hedef ölçümü kapsaması",event["gaze_coverage"])]:
            chunks.append("<dt>{}</dt><dd>{}</dd>".format(esc(title),esc(str(value))))
        chunks.append("</dl><ul>"+"".join("<li>"+esc(x)+"</li>" for x in event["reasons"])+"</ul></article>")
    segments=[]
    for g in gazerows:
        segments.append("<tr><td><button data-time='{:.4f}'>{:.2f} sn</button></td><td>{}</td><td>{}</td><td>{}</td></tr>".format(g["time_s"],g["time_s"],esc(g["target"]),esc(g["head_source"]),"{:.3f}".format(g["target_margin"]) if "target_margin" in g else "—"))
    # Break polylines at missing measurements: never draw through tracking gaps.
    paths=[];current=[]
    for r in rows:
        if r.get("pose_change_deg") is None:
            if current: paths.append(" ".join(current));current=[]
        else:
            current.append("{:.1f},{:.1f}".format(r["time_s"]*100,160-min(150,r["pose_change_deg"]*2)))
    if current: paths.append(" ".join(current))
    svg="".join("<polyline points='{}' fill='none' stroke='#52d6ce' stroke-width='2'/>".format(p) for p in paths)
    body="""<!doctype html><html lang="tr"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>İsme tepki — deney raporu</title>
<style>body{font:16px/1.5 system-ui;background:#101722;color:#ecf0f6;margin:0}main{max-width:1100px;margin:auto;padding:28px}h1{font-size:30px}h2{font-size:21px}article,.panel{background:#1b2636;border:1px solid #334256;border-radius:14px;padding:22px;margin:20px 0}video{width:100%;border-radius:10px}dt{font-weight:600;color:#8ed7d1}dd{margin:0 0 14px;overflow-wrap:anywhere}a{color:#8ed7d1}button{cursor:pointer;color:#101722;background:#8ed7d1;border:0;border-radius:5px;padding:5px 10px}table{width:100%;border-collapse:collapse}td,th{text-align:left;border-bottom:1px solid #334256;padding:7px}.small{color:#becada;font-size:14px}svg{width:100%;background:#101722}li{margin:8px 0}</style>
<main><h1>İsme tepki: ilk video deneyi</h1><p>Baş hareketi, hedef tahmini ve çağrı zamanı ayrı ölçülür. Sonuçlar araştırma prototipi çıktısıdır.</p>
<div class="panel"><video id="video" controls src="annotated.mp4"></video><p class="small">Orijinal ses korunmuştur. Eflatun işaret modelin tahminidir; mavi ok yaklaşık baş yönüdür.</p></div>
"""+"".join(chunks)+"<div class='panel'><h2>Baş pozu değişimi</h2><p>Yatay eksen: saniye. Dikey eksen: başlangıç pozuna göre 0–75°; eksik ölçümler çizilmez.</p><svg viewBox='0 0 800 190' role='img' aria-label='Baş pozu değişimi'>"+svg+"".join("<text x='{}' y='185' fill='#becada'>{}s</text>".format(i*100,i) for i in range(8))+"</svg></div><div class='panel'><h2>Hedef tahminleri</h2><p class='small'>Zamana tıklayarak videoda kontrol edin. Hedef marjı kalibre güven değildir. Baş ölçümleri 24 FPS, hedef modeli 6 FPS çalıştırılmıştır.</p><table><thead><tr><th>Zaman</th><th>Hedef</th><th>Baş takibi</th><th>Hedef marjı</th></tr></thead><tbody>"+"".join(segments)+"</tbody></table></div><div class='panel'><h2>Sınırlar</h2><ul>"+"".join("<li>"+esc(x)+"</li>" for x in result["limitations"])+"</ul><a href='result.json'>Sonuç JSON</a> · <a href='measurements.csv'>Ölçüm CSV</a> · <a href='gaze.json'>Hedef örnekleri</a></div><p class='small'>SHA256: "+result["video"]["sha256"]+"</p></main><script>document.querySelectorAll('[data-time]').forEach(b=>b.onclick=()=>{const v=document.getElementById('video');v.currentTime=Number(b.dataset.time);v.pause();v.scrollIntoView({behavior:'smooth'})});</script></html>"
    (output/"report.html").write_text(body,encoding="utf-8")
    textlines=["İSME TEPKİ — DENEY SONUCU", "Video SHA256: "+result["video"]["sha256"],""]
    for event in result["events"]:
        textlines.extend([event["label_tr"],"Baş hareketi: "+str(event["movement"]),"Yetişkin hedefi: "+str(event["adult_target_run"]),"Karar güveni: kalibre edilmedi"]+event["reasons"]+[""])
    (output/"summary.txt").write_text("\n".join(textlines),encoding="utf-8")
