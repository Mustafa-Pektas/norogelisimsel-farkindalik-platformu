"""Controlled target/crop/adapter tests; no ONNX, Tasks or speech inference."""
from types import SimpleNamespace as N
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch
import unittest
import numpy as np
from stride4_tracking import Stride4Tracker,target_crop,extract_target_crop,load_estimator,SOURCE_FILES


class Track:
    def __init__(self,*_):
        self.visible_boxes=[];self.closed=False
        self.row=dict(valid=False,rotation_matrix=None,bbox=[.3,.3,.5,.5],
            identity_status='face_landmarks',target_provenance='manual_initial_point',track_source='landmarks')
    def update(self,*_):return self.row.copy()
    def close(self):self.closed=True


class Estimator:
    def __init__(self):self.calls=[];self.closed=False;self.matrix=np.eye(3)
    def predict(self,image,index,t):
        self.calls.append((image.shape,index,t))
        return N(face_detected=True,rotation_matrix=self.matrix,flag='FALLBACK_6DREPNET',metadata={'used_6d_fallback':True})
    def reset(self):self.closed=True


class Tests(unittest.TestCase):
    def make(self):
        self.track=Track();self.est=Estimator()
        return Stride4Tracker(None,[.4,.4],None,None,tracker_factory=lambda *a:self.track,
            estimator_factory=lambda *a:(self.est,{'engine':'cascade_stride4_onnx'}))

    def test_dynamic_crop_target_point_no_video_roi_and_cleanup(self):
        tracker=self.make();frame=np.zeros((200,300,3),np.uint8)
        row=tracker.update(frame,.2)
        self.assertTrue(row['valid']);self.assertEqual(row['crop_source_xywh'],[60,20,120,120])
        self.track.row['bbox']=[.4,.3,.6,.5]
        row2=tracker.update(frame,.3)
        self.assertNotEqual(row2['crop_source_xywh'],row['crop_source_xywh'])
        self.assertEqual(self.est.calls[1][1:],(1,.3))
        tracker.close();self.assertTrue(self.est.closed);self.assertTrue(self.track.closed)

    def test_ambiguous_lost_unselected_competing_face_do_not_infer(self):
        for status in ('target_ambiguous','identity_lost_no_reacquisition','target_not_found'):
            with self.subTest(status=status):
                tracker=self.make();self.track.row['identity_status']=status
                self.assertFalse(tracker.update(np.zeros((200,300,3),np.uint8),0)['valid'])
                self.assertFalse(self.est.calls)
        tracker=self.make();self.track.visible_boxes=[[.53,.4,.57,.5]]
        row=tracker.update(np.zeros((200,300,3),np.uint8),0)
        self.assertEqual(row['measurement_status'],'stride4_competing_face');self.assertFalse(self.est.calls)

    def test_invalid_bbox_and_invalid_matrix_stay_missing(self):
        tracker=self.make();frame=np.zeros((200,300,3),np.uint8)
        self.assertIsNone(target_crop(frame,[.2,.2,.1,.1]))
        self.est.matrix=np.zeros((3,3));row=tracker.update(frame,0)
        self.assertFalse(row['valid']);self.assertIsNone(row['rotation_matrix']);self.assertIsNone(row['yaw_deg'])
        self.assertEqual(row['rejection_reason'],'invalid_rotation_matrix')

    def test_border_padding_preserves_requested_center_size_and_source_pixels(self):
        frame=np.full((200,300,3),17,dtype=np.uint8)
        for box in ([0,0,.2,.2],[.8,.8,1.,1.],[.4,0,.6,.2],[0,.4,.2,.6]):
            with self.subTest(box=box):
                crop=target_crop(frame,box);self.assertIsNotNone(crop)
                x,y,w,h=crop;self.assertEqual(w,h)
                self.assertAlmostEqual(x+w/2,(box[0]+box[2])*300/2,delta=.5)
                self.assertAlmostEqual(y+h/2,(box[1]+box[3])*200/2,delta=.5)
                image,pad=extract_target_crop(frame,crop)
                self.assertEqual(image.shape,(h,w,3));self.assertTrue(any(pad))
                self.assertEqual(pad,[max(0,-x),max(0,-y),max(0,x+w-300),max(0,y+h-200)])
                left,top,right,bottom=pad
                np.testing.assert_array_equal(image[top:h-bottom,left:w-right],17)
                mask=np.ones((h,w),bool);mask[top:h-bottom,left:w-right]=False
                self.assertTrue(np.all(image[mask]==128))

    def test_top_border_reaches_estimator_but_ambiguity_and_other_face_still_block(self):
        frame=np.full((200,300,3),17,dtype=np.uint8)
        tracker=self.make();self.track.row['bbox']=[.3,0,.5,.2]
        row=tracker.update(frame,22/24)
        self.assertTrue(row['valid']);self.assertEqual(row['crop_source_xywh'],[60,-40,120,120])
        self.assertEqual(row['crop_padding_ltrb_source_px'],[0,40,0,0])
        self.assertEqual(row['crop_padding_rgb'],[128,128,128]);self.assertEqual(row['crop_status'],'ready_padded')
        self.assertEqual(len(self.est.calls),1);self.assertIsNone(row['rejection_reason'])
        self.track.row['identity_status']='target_ambiguous'
        row=tracker.update(frame,23/24)
        self.assertFalse(row['valid']);self.assertEqual(len(self.est.calls),1)
        self.assertEqual(row['rejection_reason'],'identity_not_usable:target_ambiguous')
        self.track.row['identity_status']='face_landmarks';self.track.visible_boxes=[[.53,.02,.57,.08]]
        row=tracker.update(frame,24/24)
        self.assertEqual(row['rejection_reason'],'competing_face_in_crop');self.assertEqual(len(self.est.calls),1)

    def test_unpadded_crop_is_byte_identical_to_old_extraction(self):
        frame=np.arange(200*300*3,dtype=np.uint8).reshape(200,300,3)
        crop=target_crop(frame,[.3,.3,.5,.5]);x,y,w,h=crop
        image,padding=extract_target_crop(frame,crop)
        self.assertEqual(padding,[0,0,0,0])
        np.testing.assert_array_equal(image,frame[y:y+h,x:x+w])

    def test_actual_repnet_calls_count_per_frame_including_padded_input(self):
        class Counted(Estimator):
            def __init__(self):
                super().__init__();self.repnet=N(predict=lambda *args:None)
            def predict(self,image,index,t):
                self.repnet.predict(image,index,t)
                return super().predict(image,index,t)
        track=Track();track.row['bbox']=[.3,0,.5,.2];est=Counted()
        tracker=Stride4Tracker(None,None,None,None,tracker_factory=lambda *a:track,
            estimator_factory=lambda *a:(est,{}))
        frame=np.zeros((200,300,3),np.uint8)
        row=tracker.update(frame,0)
        self.assertEqual(row['repnet_calls_this_frame'],1);self.assertEqual(tracker.repnet_calls,1)
        track.row['identity_status']='target_ambiguous';row=tracker.update(frame,1/24)
        self.assertEqual(row['repnet_calls_this_frame'],0);self.assertEqual(tracker.repnet_calls,1)

    def test_bounded_flow_restores_model_crop_up_to_existing_2_5s_limit(self):
        for age in (0.,2.49,2.5):
            with self.subTest(age=age):
                tracker=self.make();self.track.row.update(identity_status='pose_missing_track_unconfirmed',
                    track_source='optical_flow',landmark_age_s=age)
                row=tracker.update(np.zeros((200,300,3),np.uint8),age)
                self.assertTrue(row['valid']);self.assertEqual(row['pose_target_basis'],'bounded_optical_flow')
                self.assertEqual(len(self.est.calls),1)
                self.assertEqual(row['crop_source_xywh'],[60,20,120,120])
                self.assertFalse(row['stride4_anchors_reset'])

    def test_expired_or_unknown_flow_lost_and_ambiguous_never_run_estimator(self):
        for age in (2.500001,None,float('nan'),-1.,True):
            with self.subTest(age=age):
                tracker=self.make();self.track.row.update(identity_status='pose_missing_track_unconfirmed',
                    track_source='optical_flow',landmark_age_s=age)
                row=tracker.update(np.zeros((200,300,3),np.uint8),3.)
                self.assertFalse(row['valid']);self.assertFalse(self.est.calls)
                self.assertEqual(row['rejection_reason'],'optical_flow_confirmation_expired_or_unknown')
                self.assertIsNone(row['rotation_matrix'])
        for status,source in [('identity_lost_waiting_landmarks','lost'),('identity_lost_no_reacquisition','optical_flow'),
                              ('target_ambiguous','optical_flow'),('face_landmarks','lost')]:
            with self.subTest(status=status,source=source):
                tracker=self.make();self.track.row.update(identity_status=status,track_source=source,landmark_age_s=.1)
                row=tracker.update(np.zeros((200,300,3),np.uint8),3.)
                self.assertFalse(row['valid']);self.assertFalse(self.est.calls)
                self.assertIsNone(row['rotation_matrix'])

    def test_bounded_flow_still_rejects_competing_face(self):
        tracker=self.make();self.track.row.update(identity_status='pose_missing_track_unconfirmed',
            track_source='optical_flow',landmark_age_s=1.)
        self.track.visible_boxes=[[.53,.4,.57,.5]]
        row=tracker.update(np.zeros((200,300,3),np.uint8),1.)
        self.assertFalse(row['valid']);self.assertFalse(self.est.calls)
        self.assertEqual(row['rejection_reason'],'competing_face_in_crop')

    def test_reacquisition_discards_all_old_pose_anchors_before_inference(self):
        tracker=self.make();self.track.row.update(target_reacquired=True,reacquisition_time_s=3.,reacquisition_gap_s=3.)
        old=np.eye(3)
        self.est.rep_anchor=old;self.est.kp_anchor=old;self.est.r_align=old;self.est.bridge_count=9
        from unittest.mock import Mock
        self.est.pnp=N(reset=Mock());self.est.bridge=N(reset=Mock())
        original=self.est.predict
        def predict(*args):
            self.assertIsNone(self.est.rep_anchor);self.assertIsNone(self.est.kp_anchor)
            self.assertIsNone(self.est.r_align);self.assertEqual(self.est.bridge_count,0)
            self.est.pnp.reset.assert_called_once();self.est.bridge.reset.assert_called_once()
            self.assertFalse(self.est.closed, 'Do not unload the ONNX model')
            return original(*args)
        self.est.predict=predict
        row=tracker.update(np.zeros((200,300,3),np.uint8),3.)
        self.assertTrue(row['valid']);self.assertTrue(row['stride4_anchors_reset'])
        self.assertEqual(row['reacquisition_time_s'],3.)

    def test_only_stride4_enables_reacquisition_on_default_target_tracker(self):
        with patch('fast_tracking.FastTracker',return_value=Track()) as factory:
            Stride4Tracker(None,[.4,.4],None,None,estimator_factory=lambda *a:(Estimator(),{}))
        factory.assert_called_once_with(None,[.4,.4],allow_reacquisition=True)

    def test_failed_estimator_setup_closes_target_tracker(self):
        track=Track()
        def failed(*_):raise ValueError('controlled')
        with self.assertRaises(ValueError):
            Stride4Tracker(None,None,None,None,tracker_factory=lambda *a:track,estimator_factory=failed)
        self.assertTrue(track.closed)

    def test_supplied_class_is_stride4_onnx_with_explicit_model_and_cpu_only(self):
        with TemporaryDirectory() as root:
            root=Path(root)
            for name in SOURCE_FILES:
                file=root/name;file.parent.mkdir(parents=True,exist_ok=True);file.write_text('controlled source')
            model=root/'model.onnx';model.write_bytes(b'controlled model')
            seen=[]
            class Cascade(Estimator):
                def __init__(self,**kw):
                    super().__init__();seen.append(kw)
                    self.repnet=N(onnx_path=None,session=N(get_providers=lambda:['CPUExecutionProvider']))
                def setup(self):return True
            module=N(__file__=str(root/'estimators/hybrid_estimator.py'),CascadePnpRepNetStridedEstimator=Cascade)
            import sys
            before=sys.path.copy()
            try:
                with patch('stride4_tracking.importlib.import_module',return_value=module):
                    estimator,provenance=load_estimator(root,model)
                self.assertEqual(seen,[{'stride':4,'backend':'onnx'}])
                self.assertEqual(estimator.repnet.onnx_path,str(model))
                self.assertIsNone(provenance['transitionBlend'])
                self.assertEqual(set(provenance['sourceSHA256']),set(SOURCE_FILES))
            finally:sys.path[:]=before


if __name__=='__main__':unittest.main()
