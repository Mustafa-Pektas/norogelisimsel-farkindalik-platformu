"""Explicit ONE-TIME preparation. Never imported by the analysis request path."""
import argparse,json,hashlib,importlib.metadata
from pathlib import Path


def main():
    p=argparse.ArgumentParser();p.add_argument('--download',action='store_true',required=True)
    p.add_argument('--output-dir',type=Path,required=True);a=p.parse_args()
    if a.output_dir.exists():pass
    from huggingface_hub import snapshot_download
    root=Path(snapshot_download('Systran/faster-whisper-small',local_dir=str(a.output_dir)))
    for f in ('model.bin','config.json','tokenizer.json'):
        if not (root/f).is_file():raise ValueError('Incomplete local model: '+f)
    # Actual load check is offline; model preparation does not transcribe videos.
    from faster_whisper import WhisperModel
    model=WhisperModel(str(root.resolve()),device='cpu',compute_type='int8',cpu_threads=4,local_files_only=True)
    manifest=dict(repository='Systran/faster-whisper-small',packages={n:importlib.metadata.version(n) for n in ['faster-whisper','ctranslate2','av','tokenizers','huggingface-hub']},
      sha256={f:hashlib.sha256((root/f).read_bytes()).hexdigest() for f in ('model.bin','config.json','tokenizer.json')},offline_load_passed=True)
    (root/'d01_preparation.json').write_text(json.dumps(manifest,indent=2));del model
    print('Local audio model prepared and offline-loaded; no video analysed')


if __name__=='__main__':main()
