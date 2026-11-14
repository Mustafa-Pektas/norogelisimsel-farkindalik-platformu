"""Saved-job visual evidence only. No estimator/model loading or inference."""
from pathlib import Path
import argparse,hashlib,json,sys
import cv2
import numpy as np
from PIL import Image,ImageDraw
from stride4_tracking import extract_target_crop


def review(job,out,source):
    state=json.loads((job/'job.json').read_text())
    if state['status']!='completed':raise ValueError('Completed job required')
    video=job/'upload.mp4'
    if hashlib.sha256(video.read_bytes()).hexdigest()!=state['videoHash']:raise ValueError('Video hash mismatch')
    rows=[json.loads(s) for s in (job/'run/details/frames.jsonl').read_text().splitlines()]
    if state.get('poseEngine')=='cascade_stride4_onnx':
        sys.path.insert(0,str(source.resolve()))
        from estimators.repnet360 import preprocess_numpy
    out.mkdir(parents=True,exist_ok=False);cap=cv2.VideoCapture(str(video));page=None
    try:
        for i,row in enumerate(rows):
            ok,bgr=cap.read()
            if not ok or row['frame_index']!=i:raise ValueError('Frame sequence mismatch')
            if i%12==0:page=Image.new('RGB',(1152,1024),'#202020')
            frame=Image.fromarray(cv2.cvtColor(bgr,cv2.COLOR_BGR2RGB));draw=ImageDraw.Draw(frame)
            box=row.get('bbox')
            if box:
                w,h=frame.size;draw.rectangle([box[0]*w,box[1]*h,box[2]*w,box[3]*h],outline='lime',width=4)
            frame.thumbnail((160,224));x=(i%3)*384;y=((i%12)//3)*256
            page.paste(frame,(x,y+25))
            crop=row.get('crop_source_xywh')
            if crop and row.get('crop_bgr_sha256'):
                image,padding=extract_target_crop(bgr,crop)
                if row.get('crop_padding_ltrb_source_px',padding)!=padding:raise ValueError('Padding identity mismatch')
                if hashlib.sha256(image.tobytes()).hexdigest()!=row['crop_bgr_sha256']:raise ValueError('Crop identity mismatch')
                tensor=preprocess_numpy(image)[0].transpose(1,2,0)
                rgb=np.clip(np.rint((tensor*np.array([.229,.224,.225])+np.array([.485,.456,.406]))*255),0,255).astype('uint8')
                page.paste(Image.fromarray(rgb),(x+160,y+25))
            ImageDraw.Draw(page).text((x+2,y+2),f"{i} | {row['time_s']:.3f}s | pose {row['valid']}",fill='white')
            if i%12==11 or i==len(rows)-1:page.save(out/f'page_{i//12+1:03d}.png')
    finally:cap.release()
    (out/'review.json').write_text(json.dumps(dict(videoHash=state['videoHash'],frames=len(rows),
        correctChildVisuallyVerified=None,headContainmentVerified=None,
        scope='Saved boxes and reconstructed final input; requires human review, not automated identity approval'),indent=2))


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--job',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--stride4-source',type=Path,required=True);a=p.parse_args()
    review(a.job,a.output,a.stride4_source)
