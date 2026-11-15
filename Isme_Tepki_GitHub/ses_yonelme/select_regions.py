"""Optional native ROI editor; keeps original configuration untouched."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import cv2


def main():
    parser=argparse.ArgumentParser(description="Yeni video için elle sahne bölgelerini seç")
    parser.add_argument("--video",required=True,type=Path)
    parser.add_argument("--output",required=True,type=Path,help="Yeni JSON; mevcut dosyanın üzerine yazılmaz")
    parser.add_argument("--call-start",required=True,type=float)
    parser.add_argument("--call-end",required=True,type=float)
    parser.add_argument("--name",default="Deniz")
    args=parser.parse_args()
    if args.output.exists():
        parser.error("Çıktı mevcut. Yeni bir dosya adı seçin.")
    video=args.video.resolve()
    cap=cv2.VideoCapture(str(video));ok,frame=cap.read()
    if not ok:
        parser.error("Video açılamadı.")
    h,w=frame.shape[:2];fps=cap.get(cv2.CAP_PROP_FPS);duration=cap.get(cv2.CAP_PROP_FRAME_COUNT)/fps;cap.release()
    if not 0<=args.call_start<args.call_end<=duration:
        parser.error("Çağrı aralığı video içinde olmalı.")
    config=json.loads((Path(__file__).parent/"config"/"deniz.json").read_text(encoding="utf-8"))
    def select(label):
        shown=cv2.resize(frame,(min(1000,w),round(h*min(1000,w)/w)))
        x,y,bw,bh=cv2.selectROI(label,shown,showCrosshair=True,fromCenter=False)
        cv2.destroyAllWindows()
        if bw<=0 or bh<=0:
            raise ValueError("Bölge seçilmedi: "+label)
        sh,sw=shown.shape[:2]
        return [x/sw,y/sh,(x+bw)/sw,(y+bh)/sh]
    config["child_head"]=select("1 CHILD HEAD including hair - Enter to confirm")
    config["child_search_region"]=select("2 CHILD search area for entire movement - exclude adult")
    config["adult_head"]=select("3 ADULT HEAD")
    config["adult_search_region"]=select("4 ADULT search area - exclude child")
    config["targets"][0]["bbox"]=config["adult_head"]
    config["targets"][1]["bbox"]=select("5 ADULT upper body - exclude face")
    config["targets"][2]["bbox"]=select("6 TOY region throughout video")
    config.update(video=str(video),expected_size=[w,h],expected_duration_s=duration,expected_sha256=hashlib.sha256(video.read_bytes()).hexdigest())
    config["calls"]=[{"id":"call_01","name":args.name,"language":"tr","start_s":args.call_start,"end_s":args.call_end,"name_verified":False,"name_source":"user_supplied","timing_source":"user_supplied","speaker_target_id":None,"speaker_source":"unresolved"}]
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(config,ensure_ascii=False,indent=2),encoding="utf-8")
    print(args.output)


if __name__=="__main__":
    main()
