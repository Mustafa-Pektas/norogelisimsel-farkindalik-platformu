"""Target-gated adapter to the supplied benchmark's unchanged Stride4 ONNX estimator.

The transport stays API 1.2. A tracked box is not verified child identity;
numeric SO(3) validity is not physical pose accuracy. No video-specific ROI.
"""
from pathlib import Path
import hashlib
import importlib
import math
import sys
import time
import numpy as np
from motion_candidates import rotation

ENGINE = 'cascade_stride4_onnx'
SOURCE_FILES = (
    'estimators/base.py', 'estimators/hybrid_estimator.py',
    'estimators/mediapipe_pnp.py', 'estimators/optical_flow.py',
    'estimators/repnet360.py', 'estimators/blazeface_kp.py',
    'common/types.py', 'common/geometry.py', 'common/filters.py',
)


def target_crop(frame, box):
    """Square tracking-derived crop, 2x face size, preserving center and size.

    CenterCrop(224) removes a 16px margin after Resize(256); final head
    containment must still be reviewed. No claim that a face box is a head mask.
    """
    return crop_geometry(frame,box)[0]


def crop_geometry(frame, box):
    """Return geometry and an explicit rejection reason; outside bounds is allowed."""
    if not isinstance(box, (list, tuple)) or len(box) != 4:
        return None,'missing_or_invalid_bbox'
    if any(not isinstance(v, (float, int)) or not math.isfinite(v) or not 0 <= v <= 1 for v in box):
        return None,'invalid_bbox_coordinates'
    h, w = frame.shape[:2]
    x1,y1,x2,y2 = box
    side = int(math.ceil(2 * max((x2-x1)*w, (y2-y1)*h)))
    if x2 <= x1 or y2 <= y1:
        return None,'degenerate_bbox'
    if side < 16:
        return None,'crop_too_small'
    x = int(round((x1+x2)*w/2-side/2))
    y = int(round((y1+y2)*h/2-side/2))
    return (x,y,side,side),None


def extract_target_crop(frame,crop):
    """Keep requested geometry; explicitly fill source-external pixels with RGB128."""
    x,y,w,h=crop;source_h,source_w=frame.shape[:2]
    left,top,right,bottom=max(0,x),max(0,y),min(source_w,x+w),min(source_h,y+h)
    if right<=left or bottom<=top:
        raise ValueError('Crop does not intersect source')
    padding=[max(0,-x),max(0,-y),max(0,x+w-source_w),max(0,y+h-source_h)]
    if not any(padding):
        return np.ascontiguousarray(frame[y:y+h,x:x+w]),padding
    image=np.full((h,w,frame.shape[2]),128,dtype=frame.dtype)
    image[top-y:bottom-y,left-x:right-x]=frame[top:bottom,left:right]
    return image,padding


def load_estimator(source, model):
    source, model = Path(source).resolve(), Path(model).resolve()
    if not source.is_dir() or not model.is_file():
        raise ValueError('Stride4 source/model unavailable')
    files = [source/name for name in SOURCE_FILES]
    if not all(p.is_file() for p in files):
        raise ValueError('Incomplete benchmark modules')
    sys.path.insert(0,str(source))
    module = importlib.import_module('estimators.hybrid_estimator')
    if Path(module.__file__).resolve() != source/'estimators/hybrid_estimator.py':
        raise ValueError('Unexpected benchmark import origin')
    estimator = module.CascadePnpRepNetStridedEstimator(stride=4,backend='onnx')
    estimator.repnet.onnx_path = str(model)
    try:
        if not estimator.setup():
            raise ValueError('Stride4 runtime setup failed; no engine fallback')
        if estimator.repnet.session.get_providers() != ['CPUExecutionProvider']:
            raise ValueError('Stride4 requires CPUExecutionProvider only')
    except BaseException:
        estimator.reset()
        raise
    provenance = dict(engine=ENGINE,stride=4,transitionBlend=None,
        cropRule='tracked-face-square-2x-centered-rgb128-pad-v2',paddingRGB=[128,128,128],
        targetPolicy='bounded-flow-and-unique-reacquisition-v2',
        targetAssociation=dict(minIoU=.15,maxHistogramL2=.45,longGapS=2.5),
        sourceSHA256={name:hashlib.sha256((source/name).read_bytes()).hexdigest() for name in SOURCE_FILES},
        onnxSHA256=hashlib.sha256(model.read_bytes()).hexdigest(),
        intraOpThreads=4,interOpThreads=1,providers=['CPUExecutionProvider'])
    return estimator,provenance


class Stride4Tracker:
    def __init__(self, task, point, source, model, *, tracker_factory=None, estimator_factory=load_estimator):
        if tracker_factory is None:
            from fast_tracking import FastTracker
            tracker_factory = lambda task,point: FastTracker(task,point,allow_reacquisition=True)
        begin=time.perf_counter();self.track = tracker_factory(task,point)
        target_load=time.perf_counter()-begin;begin=time.perf_counter()
        try:
            self.estimator,self.provenance = estimator_factory(source,model)
        except BaseException:
            self.track.close()
            raise
        self.load_timings=dict(target_tracker_load_s=target_load,cascade_load_s=time.perf_counter()-begin)
        self.repnet_calls=0
        if hasattr(self.estimator,'repnet'):
            original=self.estimator.repnet.predict
            def counted(*args,**kwargs):
                self.repnet_calls+=1
                return original(*args,**kwargs)
            self.estimator.repnet.predict=counted
        self.index=0

    def update(self, frame, t):
        row=self.track.update(frame,t);index=self.index;self.index+=1
        reacquired=row.get('target_reacquired',False)
        if reacquired:
            # Do not unload ONNX, but discard every old pose/bridge reference.
            self.estimator.rep_anchor=None;self.estimator.kp_anchor=None
            self.estimator.r_align=None;self.estimator.bridge_count=0
            for name in ('pnp','bridge'):
                component=getattr(self.estimator,name,None)
                if component is not None:component.reset()
        row=dict(row,valid=False,rotation_matrix=None,pitch_deg=None,yaw_deg=None,roll_deg=None,
            measurement_status='stride4_target_unavailable',pose_engine=ENGINE,
            crop_source_xywh=None,crop_status='not_attempted',crop_padding_ltrb_source_px=None,
            crop_padding_rgb=None,rejection_reason=None,repnet_calls_this_frame=0,stride4_anchors_reset=reacquired)
        age=row.get('landmark_age_s')
        flow_in_bound=(row.get('identity_status')=='pose_missing_track_unconfirmed'
            and row.get('track_source')=='optical_flow'
            and type(age) in (int,float) and math.isfinite(age) and 0<=age<=2.5)
        landmarks=(row.get('identity_status')=='face_landmarks' and row.get('track_source')=='landmarks')
        usable=row.get('target_provenance')=='manual_initial_point' and (landmarks or flow_in_bound)
        row['pose_target_basis']='confirmed_landmarks' if landmarks and usable else 'bounded_optical_flow' if flow_in_bound and usable else None
        target_reason=('target_not_user_selected' if row.get('target_provenance')!='manual_initial_point'
            else 'optical_flow_confirmation_expired_or_unknown' if row.get('identity_status')=='pose_missing_track_unconfirmed' and row.get('track_source')=='optical_flow' and not flow_in_bound
            else 'identity_not_usable:'+str(row.get('identity_status'))
            if row.get('identity_status')!='face_landmarks'
            else 'tracking_not_usable:'+str(row.get('track_source')))
        crop,reason=crop_geometry(frame,row.get('bbox')) if usable else (None,target_reason)
        if crop is None:
            row.update(crop_status='rejected' if usable else 'not_attempted',rejection_reason=reason)
            # Do not carry a keypoint anchor across missing/ambiguous identity.
            self.estimator.rep_anchor=None;self.estimator.kp_anchor=None
            return row
        x,y,w,h=crop
        row['crop_source_xywh']=list(crop)
        # Reject a known competing face in this crop, even if the tracker itself
        # has a unique selected identity. The estimator cannot select by point.
        for other in getattr(self.track,'visible_boxes',[]):
            if other==row.get('bbox'):
                continue
            from fast_tracking import box_iou
            if box_iou(other,row['bbox'])>.5:
                continue
            ox=(other[0]+other[2])*frame.shape[1]/2
            oy=(other[1]+other[3])*frame.shape[0]/2
            if x<=ox<=x+w and y<=oy<=y+h:
                row['measurement_status']='stride4_competing_face'
                row.update(crop_status='rejected',rejection_reason='competing_face_in_crop')
                self.estimator.rep_anchor=None;self.estimator.kp_anchor=None
                return row
        image,padding=extract_target_crop(frame,crop)
        row.update(crop_status='ready_padded' if any(padding) else 'ready_unpadded',
            crop_padding_ltrb_source_px=padding,crop_padding_rgb=[128,128,128] if any(padding) else None)
        calls_before=self.repnet_calls
        pose=self.estimator.predict(image,index,t)
        row['repnet_calls_this_frame']=self.repnet_calls-calls_before
        matrix=rotation(pose.rotation_matrix) if pose.face_detected and pose.rotation_matrix is not None else None
        row.update(crop_source_xywh=list(crop),crop_bgr_sha256=hashlib.sha256(image.tobytes()).hexdigest(),
            estimator_flag=pose.flag,estimator_metadata={k:pose.metadata.get(k) for k in ('used_6d_fallback','used_kp_bridge')},
            measurement_status='stride4_pose_rejected',
            rejection_reason='invalid_rotation_matrix' if pose.face_detected else 'estimator_pose_unavailable')
        if matrix is not None:
            from compare_headpose_methods import euler_xyz
            pitch,yaw,roll=euler_xyz(matrix)
            row.update(valid=True,rotation_matrix=matrix.tolist(),pitch_deg=pitch,yaw_deg=yaw,roll_deg=roll,
                measurement_status='cascade_stride4_pose',rejection_reason=None)
        return row

    def close(self):
        try:self.estimator.reset()
        finally:self.track.close()
