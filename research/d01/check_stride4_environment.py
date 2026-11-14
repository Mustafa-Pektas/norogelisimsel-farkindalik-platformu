"""Dependency-only check. No download, model load, inference or video access."""
import importlib
import importlib.metadata
import json


def check():
    result={};ok=True
    for name,dist in [('numpy','numpy'),('cv2','opencv-python'),('PIL','pillow'),('scipy','scipy'),
                      ('mediapipe','mediapipe'),('onnxruntime','onnxruntime'),('faster_whisper','faster-whisper')]:
        try:
            module=importlib.import_module(name)
            try:version=importlib.metadata.version(dist)
            except importlib.metadata.PackageNotFoundError:version=getattr(module,'__version__',None)
            result[name]={'imported':True,'version':version}
            if name=='mediapipe':
                supported=all(hasattr(module,k) for k in ['solutions','tasks'])
                result[name]['legacySolutionsAndTasks']=supported;ok=ok and supported
            if name=='onnxruntime':
                supported='CPUExecutionProvider' in module.get_available_providers()
                result[name]['cpuProviderAvailable']=supported;ok=ok and supported
        except Exception as e:
            result[name]={'imported':False,'errorType':type(e).__name__};ok=False
    return {'ready':ok,'scope':'imports_only_no_model_execution','packages':result}


if __name__=='__main__':
    result=check();print(json.dumps(result,indent=2));raise SystemExit(0 if result['ready'] else 1)
