"""Tasks multi-face association + unchanged supplied FaceTrack flow/PnP.

No age/child classifier. Ambiguity is missing data; long loss is never silently
reinitialized to whichever adult remains. A point is optional human identity input.
"""
from pathlib import Path
import importlib.util
import hashlib
from types import SimpleNamespace
import numpy as np


def box_iou(a,b):
    intersection=max(0,min(a[2],b[2])-max(a[0],b[0]))*max(0,min(a[3],b[3])-max(a[1],b[1]))
    union=(a[2]-a[0])*(a[3]-a[1])+(b[2]-b[0])*(b[3]-b[1])-intersection
    return intersection/union if union>0 else 0.


class IdentitySelection:
    def __init__(self, point=None):
        self.point=point;self.started=False;self.established=False;self.box=None;self.hist=None
        self.last=None;self.status='not_selected';self.provenance='not_determined'

    def choose(self, faces, t, predicted_box=None):
        if not self.started:
            self.started=True
            choices=[f for f in faces if self.point is None or f['box'][0]<=self.point[0]<=f['box'][2] and f['box'][1]<=self.point[1]<=f['box'][3]]
            if len(choices)!=1:
                self.status='target_ambiguous' if len(choices)>1 else 'target_not_found'
                return None
            chosen=choices[0];self.established=True
            self.provenance='manual_initial_point' if self.point is not None else 'single_face_candidate_role_unverified'
        else:
            if not self.established:return None
            if t-self.last>2.5:
                self.status='identity_lost_no_reacquisition';return None
            box=predicted_box or self.box
            choices=[]
            for face in faces:
                overlap=box_iou(box,face['box']);distance=float(np.linalg.norm(np.array(face['hist'])-self.hist))
                if overlap>=.15 and distance<=.45:choices.append(face)
            if len(choices)!=1:
                self.status='target_ambiguous' if len(choices)>1 else 'pose_missing_track_unconfirmed'
                return None
            chosen=choices[0]
        self.box=chosen['box'];self.hist=chosen['hist'];self.last=t;self.status='face_landmarks'
        return chosen


def call_phase(start, call_start, call_end):
    if call_start is None or call_end is None:return 'call_unknown'
    if start is None:return 'unknown_movement_start'
    if start<call_start:return 'before_call'
    return 'during_call' if start<=call_end else 'after_call'


class FastTracker:
    def __init__(self, task, point=None):
        import cv2
        import mediapipe as mp
        from mediapipe.tasks.python import vision
        from mediapipe.tasks import python
        self.cv2=cv2;self.mp=mp;self.selector=IdentitySelection(point);self.t=0.;self.faces=0
        path=Path(__file__).parent/'vendor/friend_vision.py'
        if hashlib.sha256(path.read_bytes()).hexdigest()!='4fbe1f9049ccacef00fdfd73028b5a697e57978abdb05de950f9e51012c8a9e4':raise ValueError('Supplied vision provenance mismatch')
        self.detector=vision.FaceLandmarker.create_from_options(vision.FaceLandmarkerOptions(
            base_options=python.BaseOptions(model_asset_path=str(task),delegate=python.BaseOptions.Delegate.CPU),
            running_mode=vision.RunningMode.IMAGE,num_faces=5,min_face_detection_confidence=.35))
        spec=importlib.util.spec_from_file_location('fast_friend_vision',path)
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);self.module=module
        module.mp=SimpleNamespace(solutions=SimpleNamespace(face_mesh=SimpleNamespace(FaceMesh=lambda **_:self)))
        self.track=module.FaceTrack([0,0,1,1],[0,0,1,1],2.5)

    def process(self,rgb):
        self.faces=0;faces=[];h,w=rgb.shape[:2]
        # Scale search without a human-drawn box. Afterwards follow only the
        # established track; never jump to a scene-wide surviving adult face.
        if self.selector.established:
            box=self.track.box;cx=(box[0]+box[2])*w/2;cy=(box[1]+box[3])*h/2
            side=min(max(320.,(box[2]-box[0])*w*2,(box[3]-box[1])*h*2),w,h)
            x=int(max(0,min(w-side,cx-side/2)));y=int(max(0,min(h-side,cy-side/2)))
            windows=[(x,y,int(side),int(side))]
        else:
            side=min(w,h);windows=[(0,0,w,h),(0,0,side,side),(w-side,h-side,side,side)]
        for ox,oy,cw,ch in windows:
            image=np.ascontiguousarray(rgb[oy:oy+ch,ox:ox+cw])
            detected=self.detector.detect(self.mp.Image(image_format=self.mp.ImageFormat.SRGB,data=image))
            for local in detected.face_landmarks:
                points=[SimpleNamespace(x=(p.x*cw+ox)/w,y=(p.y*ch+oy)/h) for p in local]
                xy=np.array([[p.x,p.y] for p in points]);lo=xy.min(axis=0);hi=xy.max(axis=0)
                box=[float(lo[0]),float(lo[1]),float(hi[0]),float(hi[1])]
                if any(box_iou(box,f['box'])>.5 for f in faces):continue
                x1,y1=max(0,int(lo[0]*w)),max(0,int(lo[1]*h));x2,y2=min(w,int(hi[0]*w)),min(h,int(hi[1]*h))
                crop=rgb[y1:y2,x1:x2]
                if crop.size==0:continue
                hist=self.cv2.calcHist([crop],[0,1,2],None,[4,4,4],[0,256]*3).ravel();hist/=max(float(hist.sum()),1.)
                faces.append(dict(box=box,hist=hist,points=points))
        self.faces=len(faces)
        chosen=self.selector.choose(faces,self.t,self.track.box if self.selector.established else None)
        return SimpleNamespace(multi_face_landmarks=[] if chosen is None else [SimpleNamespace(landmark=chosen['points'])])

    def update(self,frame,t):
        self.t=t;track=self.track.update(frame,t)
        status=self.selector.status
        usable=self.selector.established and status not in ('target_ambiguous','identity_lost_no_reacquisition')
        source=track['source'] if usable else 'lost'
        pose=self.module.head_pose(track['landmarks'],frame.shape[1],frame.shape[0],12) if usable else {}
        matrix=None
        if pose.get('rotation_vector') is not None:
            from motion_candidates import rotation
            matrix=rotation(self.cv2.Rodrigues(np.array(pose['rotation_vector']))[0])
        valid=matrix is not None
        return dict(track_source=source,identity_status=status,face_count=self.faces,target_provenance=self.selector.provenance,
            valid=valid,rotation_matrix=matrix.tolist() if valid else None,
            pitch_deg=pose.get('pitch_deg') if valid else None,yaw_deg=pose.get('yaw_deg') if valid else None,roll_deg=pose.get('roll_deg') if valid else None,
            measurement_status='face_landmarks_pose' if valid else 'face_landmarks_pose_rejected' if track['landmarks'] is not None and usable else 'optical_flow_only' if source=='optical_flow' else 'tracking_lost',
            flow_points=track['flow_points'],bbox=track['bbox'] if self.selector.established else None)

    def close(self):self.detector.close()
