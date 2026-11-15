import unittest
import numpy as np
import cv2
from sesyon.vision import head_pose


class PoseTests(unittest.TestCase):
    def test_tilted_small_face_returns_finite_front_camera_pose(self):
        # Regression: uninitialized ITERATIVE PnP could choose a behind-camera
        # pose for this oblique, small face geometry. Generate an independent
        # physical scene and verify angular recovery, not implementation details.
        model=np.array([[0,0,0],[0,330,65],[-225,-170,135],[225,-170,135],[-150,150,125],[150,150,125]],float)
        camera=np.array([[1280,0,640],[0,1280,360],[0,0,1]],float)
        expected=np.array([.2,-.9,.35],float)
        projected=cv2.projectPoints(model,expected,np.array([-600,35,8200],float),camera,np.zeros(4))[0].reshape(-1,2)
        landmarks=np.zeros((468,2));landmarks[[1,152,33,263,61,291]]=projected
        pose=head_pose(landmarks,1280,720,12)
        self.assertIn("rotation_vector",pose)
        got=cv2.Rodrigues(np.array(pose["rotation_vector"]))[0]
        ref=cv2.Rodrigues(expected)[0]
        error=np.degrees(np.arccos(np.clip((np.trace(got@ref.T)-1)/2,-1,1)))
        self.assertLess(error,1)

    def test_no_landmarks_no_invented_pose(self):
        self.assertEqual(head_pose(None,1280,720,12),{})


if __name__=="__main__":
    unittest.main()
