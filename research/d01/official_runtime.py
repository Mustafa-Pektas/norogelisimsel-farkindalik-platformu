"""Lazy official CPU runtime and preprocessing shared by research runners."""
from pathlib import Path
import importlib
import math
import sys


def input_transforms():
    from torchvision import transforms
    return (transforms.Resize(256),transforms.CenterCrop(224),
        transforms.Compose([transforms.ToTensor(),transforms.Normalize([.485,.456,.406],[.229,.224,.225])]))


def load_official_model(source, weights):
    import torch
    import torchvision
    source=Path(source).resolve()/'sixdrepnet360'
    sys.path.insert(0,str(source))
    official=importlib.import_module('test'); utils=importlib.import_module('utils')
    if Path(official.__file__).resolve()!=source/'test.py' or Path(utils.__file__).resolve()!=source/'utils.py':
        raise ValueError('Official module resolved to a different source directory')
    model=official.SixDRepNet360(torchvision.models.resnet.Bottleneck,[3,4,6,3],6).cpu()
    state=torch.load(weights,map_location='cpu',weights_only=True)
    state=state['model_state_dict'] if 'model_state_dict' in state else state
    missing=sorted(set(model.state_dict())-set(state)); unexpected=sorted(set(state)-set(model.state_dict()))
    model.load_state_dict(state,strict=True);model.eval()
    return model,utils,dict(missing_keys=missing,unexpected_keys=unexpected,strict_load_ok=True)


class OfficialRuntime:
    def __init__(self, source, weights, threads):
        import time
        import torch
        import numpy as np
        from PIL import Image
        from motion_candidates import angle_deg
        torch.set_num_threads(threads)
        self.resize,self.crop,self.normalize=input_transforms()
        started=time.perf_counter()
        self.model,self.utils,self.checks=load_official_model(source,weights)
        self.timings={'model_load_s':time.perf_counter()-started}
        from pilot_metrics import environment
        self.environment=environment(torch,str(next(self.model.parameters()).device))
        assert torch.allclose(self.normalize(Image.new('RGB',(224,224),(255,0,0)))[:,0,0],
            torch.tensor([(1-.485)/.229,-.456/.224,-.406/.225]),atol=1e-6)
        assert torch.allclose(self.utils.compute_euler_angles_from_rotation_matrices(torch.eye(3).unsqueeze(0)),torch.zeros((1,3)),atol=1e-6)
        known=torch.tensor(self.utils.get_R(.2,-.3,.4),dtype=torch.float32).unsqueeze(0)
        assert torch.allclose(self.utils.compute_euler_angles_from_rotation_matrices(known),torch.tensor([[.2,-.3,.4]]),atol=1e-6)
        image=np.zeros((120,120,3),np.uint8);self.utils.draw_axis(image,0.,0.,0.,tdx=50,tdy=50,size=30)
        assert image[50,78].tolist()==[0,0,255] and image[78,50].tolist()==[0,255,0]
        assert angle_deg(np.eye(3),np.eye(3))==0 and abs(angle_deg(np.eye(3),self.utils.get_R(0,0,math.pi/2))-90)<1e-10
        self.checks.update(rgb_normalization=True,euler_identity=True,euler_known_rotation=True,zero_axis=True,so3_identity_and_90deg=True)

    def prepare(self, image):
        import torch
        image=self.crop(self.resize(image));tensor=self.normalize(image)
        assert image.mode=='RGB' and image.size==(224,224) and tensor.shape==(3,224,224) and torch.isfinite(tensor).all()
        return image,tensor

    def predict(self, tensor):
        import torch
        import numpy as np
        import time
        from motion_candidates import rotation
        start=time.perf_counter()
        with torch.inference_mode(): result=self.model(tensor.unsqueeze(0).cpu())
        elapsed=time.perf_counter()-start
        if result.shape!=(1,3,3) or not torch.isfinite(result).all():raise ValueError('Invalid model output')
        matrix=result[0].cpu().numpy().astype(np.float64)
        if rotation(matrix) is None:raise ValueError('Rotation determinant/orthogonality check failed')
        angles=self.utils.compute_euler_angles_from_rotation_matrices(result)[0]*180/math.pi
        if not all(math.isfinite(float(v)) for v in angles):raise ValueError('Nonfinite official Euler output')
        return dict(rotation_matrix=matrix.tolist(),pitch_deg=float(angles[0]),yaw_deg=float(angles[1]),roll_deg=float(angles[2]),
            determinant=float(np.linalg.det(matrix)),max_orthogonality_error=float(np.max(abs(matrix.T@matrix-np.eye(3)))),inference_s=elapsed,valid=True)
