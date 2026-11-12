"""MediaPipe landmarks + conservative optical flow fallback + approximate PnP."""
import cv2
import numpy as np
import mediapipe as mp


def clamp_box(box):
    x1,y1,x2,y2 = np.clip(box,0,1).tolist()
    return [x1,y1,max(x1+0.001,x2),max(y1+0.001,y2)]


def pixels(box,w,h):
    return tuple(int(round(v*d)) for v,d in zip(box,(w,h,w,h)))


class FaceTrack:
    def __init__(self,box,search,max_gap_s):
        self.box = list(box)
        self.search = search
        self.max_gap_s = max_gap_s
        self.last_observed = -1e6
        self.previous = None
        self.points = None
        self.mesh = mp.solutions.face_mesh.FaceMesh(static_image_mode=True,max_num_faces=1,
            refine_landmarks=False,min_detection_confidence=0.35)

    def update(self,frame,t):
        h,w = frame.shape[:2]
        gray = cv2.cvtColor(frame,cv2.COLOR_BGR2GRAY)
        flow_ok = False
        flow_count = 0
        if self.previous is not None and self.points is not None and len(self.points)>=6:
            q,st,_ = cv2.calcOpticalFlowPyrLK(self.previous,gray,self.points,None,winSize=(21,21),maxLevel=3)
            if q is not None:
                back,bst,_ = cv2.calcOpticalFlowPyrLK(gray,self.previous,q,None,winSize=(21,21),maxLevel=3)
                if back is not None:
                    good = (st.ravel()==1)&(bst.ravel()==1)&(np.linalg.norm(back-self.points,axis=2).ravel()<1.5)
                    p0,p1 = self.points[good].reshape(-1,2),q[good].reshape(-1,2)
                    flow_count = len(p0)
                    if flow_count >= 6:
                        shift = np.median(p1-p0,axis=0)/[w,h]
                        candidate = clamp_box(np.array(self.box)+np.tile(shift,2))
                        cx,cy = (candidate[0]+candidate[2])/2,(candidate[1]+candidate[3])/2
                        a,b,c,d = self.search
                        if a<cx<c and b<cy<d and np.linalg.norm(shift)<0.05:
                            self.box = candidate
                            flow_ok = True
        # Wider fixed search region is deliberately manually assigned to one person.
        sx1,sy1,sx2,sy2 = pixels(self.search,w,h)
        crop = frame[sy1:sy2,sx1:sx2]
        result = self.mesh.process(cv2.cvtColor(crop,cv2.COLOR_BGR2RGB))
        points = None
        if result.multi_face_landmarks:
            lm = result.multi_face_landmarks[0].landmark
            points = np.array([[p.x*(sx2-sx1)+sx1,p.y*(sy2-sy1)+sy1] for p in lm],dtype=np.float64)
            lo,hi = points.min(axis=0),points.max(axis=0)
            extent = hi-lo
            candidate = clamp_box([(lo[0]-.18*extent[0])/w,(lo[1]-.32*extent[1])/h,
                                   (hi[0]+.18*extent[0])/w,(hi[1]+.08*extent[1])/h])
            cx,cy = (candidate[0]+candidate[2])/2,(candidate[1]+candidate[3])/2
            a,b,c,d = self.search
            # Reject out-of-crop/hallucinated landmark configurations.
            if not (a<cx<c and b<cy<d and 24<extent[0]<w*.5 and 30<extent[1]<h*.7):
                points = None
            else:
                self.box = candidate
                self.last_observed = t
        source = "landmarks" if points is not None else "optical_flow" if flow_ok and t-self.last_observed <= self.max_gap_s else "lost"
        mask = np.zeros_like(gray)
        x1,y1,x2,y2 = pixels(self.box,w,h)
        mask[y1:y2,x1:x2] = 255
        self.points = cv2.goodFeaturesToTrack(gray,mask=mask,maxCorners=80,qualityLevel=.01,minDistance=5)
        self.previous = gray
        return {"bbox":self.box.copy(),"source":source,"flow_points":flow_count,"landmarks":points}

    def close(self):
        self.mesh.close()


def head_pose(points,width,height,max_error):
    if points is None:
        return {}
    idx = [1,152,33,263,61,291]
    image = points[idx]
    # Generic face; image y down, model z into face. Intrinsics are approximate.
    model = np.array([[0,0,0],[0,330,65],[-225,-170,135],[225,-170,135],[-150,150,125],[150,150,125]],dtype=np.float64)
    camera = np.array([[width,0,width/2],[0,width,height/2],[0,0,1]],dtype=np.float64)
    # SQPnP gives a global initialization. ITERATIVE without an initial pose can
    # converge to a mirrored, behind-camera solution for a small profile face.
    ok,rvec,tvec = cv2.solvePnP(model,image,camera,np.zeros(4),flags=cv2.SOLVEPNP_SQPNP)
    if not ok or tvec[2,0]<=0:
        return {}
    rvec,tvec=cv2.solvePnPRefineLM(model,image,camera,np.zeros(4),rvec,tvec)
    if tvec[2,0]<=0:
        return {}
    proj,_=cv2.projectPoints(model,rvec,tvec,camera,np.zeros(4))
    error=float(np.sqrt(np.mean(np.sum((proj.reshape(-1,2)-image)**2,axis=1))))
    if not np.isfinite(error) or error>max_error:
        return {"pose_reprojection_px":error}
    rotation,_=cv2.Rodrigues(rvec)
    angles=cv2.RQDecomp3x3(rotation)[0]
    axis,_=cv2.projectPoints(np.array([[0,0,0],[0,0,-250]],dtype=float),rvec,tvec,camera,np.zeros(4))
    return {"rotation_vector":rvec.ravel().tolist(),"pitch_deg":float(angles[0]),
            "yaw_deg":float(angles[1]),"roll_deg":float(angles[2]),
            "pose_reprojection_px":error,"head_axis_px":axis.reshape(-1,2).tolist()}


def add_pose_change(rows,call,settings):
    base=[r for r in rows if call["start_s"]-settings["baseline_s"]<=r["time_s"]<call["start_s"]-settings["baseline_guard_s"] and r.get("rotation_vector") is not None]
    if len(base)<settings["min_baseline_samples"]:
        return
    # Rotation medoid avoids wraparound and picks an actually observed baseline pose.
    mats=[cv2.Rodrigues(np.array(r["rotation_vector"]))[0] for r in base]
    def angle(a,b):
        return float(np.degrees(np.arccos(np.clip((np.trace(a@b.T)-1)/2,-1,1))))
    ref=mats[int(np.argmin([sum(angle(a,b) for b in mats) for a in mats]))]
    for row in rows:
        if row.get("rotation_vector") is not None:
            row["pose_change_deg"]=angle(cv2.Rodrigues(np.array(row["rotation_vector"]))[0],ref)
