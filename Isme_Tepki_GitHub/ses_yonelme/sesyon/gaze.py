"""Official Gaze-LLE adapter. Heatmaps are not behavioral confidence."""
import numpy as np


class GazeEstimator:
    def __init__(self,settings):
        import torch
        self.torch=torch
        torch.set_num_threads(settings["cpu_threads"])
        self.device=("cuda" if torch.cuda.is_available() else "cpu") if settings["device"]=="auto" else settings["device"]
        # Gaze-LLE requests DINOv2 main internally, which no longer supports Python 3.9.
        # Route only that nested request to the verified official revision.
        from unittest.mock import patch
        original_load = torch.hub.load
        dinov2_repo = settings.get("dinov2_repo", "facebookresearch/dinov2:85a24602099d397264d5b30461ad7f3bfd726ca1")

        def load_pinned(repo, *args, **kwargs):
            if repo == "facebookresearch/dinov2":
                repo = dinov2_repo
                kwargs.update(trust_repo=True, skip_validation=True)
            return original_load(repo, *args, **kwargs)

        with patch.object(torch.hub, "load", new=load_pinned):
            self.model,self.transform=torch.hub.load(settings["gaze_repo"],settings["gaze_model"],trust_repo=True,verbose=False)
        self.model.to(self.device).eval()
        self.settings=settings

    def predict(self,frame,head_box,targets):
        from PIL import Image
        import cv2
        inputs={"images":self.transform(Image.fromarray(cv2.cvtColor(frame,cv2.COLOR_BGR2RGB))).unsqueeze(0).to(self.device),"bboxes":[[tuple(head_box)]]}
        with self.torch.inference_mode():
            out=self.model(inputs)
        heat=out["heatmap"][0][0].cpu().numpy()
        inframe=float(out["inout"][0][0].cpu())
        h,w=heat.shape
        yi,xi=np.unravel_index(heat.argmax(),heat.shape)
        point=((xi+.5)/w,(yi+.5)/h)
        peak=float(heat.max())
        # Relative per-region maximum is a diagnostic; area sums bias larger ROIs.
        scores={}
        for target in targets:
            x1,y1,x2,y2=target["bbox"]
            roi=heat[max(0,int(y1*h)):min(h,int(np.ceil(y2*h))),max(0,int(x1*w)):min(w,int(np.ceil(x2*w)))]
            scores[target["id"]]=float(roi.max()/max(peak,1e-8)) if roi.size else 0.
        order=sorted(scores,key=scores.get,reverse=True)
        margin=scores[order[0]]-scores[order[1]] if len(order)>1 else 1.
        # Require the global maximum to lie inside a target, not merely nearest to it.
        contains=[t["id"] for t in targets if t["bbox"][0]<=point[0]<=t["bbox"][2] and t["bbox"][1]<=point[1]<=t["bbox"][3]]
        mass=np.maximum(heat,0);mass=mass/max(float(mass.sum()),1e-9)
        yy,xx=np.mgrid[:h,:w];xx=(xx+.5)/w;yy=(yy+.5)/h
        mx,my=float((mass*xx).sum()),float((mass*yy).sum())
        spread=float(np.sqrt((mass*((xx-mx)**2+(yy-my)**2)).sum()))
        s=self.settings
        if inframe<s["min_in_frame"]:
            label="offscreen"
        elif not contains or peak<s["min_heatmap_peak"] or margin<s["min_target_margin"] or spread>s["max_heatmap_spread"]:
            label="ambiguous"
        else:
            label=order[0]
        return {"target":label,"gaze_point":list(point),"in_frame_score":inframe,
                "heatmap_peak":peak,"target_margin":margin,"heatmap_spread":spread,
                "region_scores":scores},heat
