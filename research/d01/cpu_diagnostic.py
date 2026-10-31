"""Bounded, opt-in CPU diagnostic on three recorded pilot inputs; no video decode."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

FRAMES = (0, 36, 72)

def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as f:
        for block in iter(lambda: f.read(1024*1024), b''):
            h.update(block)
    return h.hexdigest()

def save(path, value):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(value, indent=2, allow_nan=False), encoding='utf-8')
    temporary.replace(path)

def cpu_info():
    info = dict(logical_cpus=os.cpu_count(), affinity=None, cgroup=[],
                thread_environment={k: os.environ.get(k) for k in
                    ('OMP_NUM_THREADS', 'MKL_NUM_THREADS', 'OPENBLAS_NUM_THREADS')})
    if hasattr(os, 'sched_getaffinity'):
        info['affinity'] = sorted(os.sched_getaffinity(0))
    try:
        entries = Path('/proc/self/cgroup').read_text().splitlines()
        unified = next((e.split(':', 2)[2] for e in entries if e.startswith('0::')), None)
        info['cgroup_version'] = 'v2' if unified is not None else 'v1_or_unresolved'
        if unified is not None:
            root = Path('/sys/fs/cgroup')
            current = root / unified.lstrip('/')
            for _ in range(32):
                row = {'path': str(current)}
                for name in ('cpu.max', 'cpu.stat', 'cpuset.cpus.effective'):
                    try: row[name] = (current/name).read_text().strip()
                    except OSError: row[name] = None
                info['cgroup'].append(row)
                if current == root: break
                current = current.parent
    except OSError:
        info['cgroup_version'] = 'unavailable'
    return info

def worker(args):
    # Each condition starts a new Python process. Only this process changes threads.
    from official_runtime import OfficialRuntime, input_transforms
    import torch
    from PIL import Image
    torch.set_num_interop_threads(4)
    run = args.recorded_run.resolve()
    protocol = json.loads((Path(__file__).parent/'parameters/pilot_v1.json').read_text())
    settings = json.loads((run/'settings.json').read_text())
    if settings['protocol'] != protocol:
        raise ValueError('Recorded protocol differs from current fixed protocol')
    if sha(args.weights) != protocol['weights_sha256']:
        raise ValueError('Weight hash mismatch')
    for name, digest in protocol['official_source_sha256'].items():
        if sha(args.official_source/'sixdrepnet360'/name) != digest:
            raise ValueError('Official source hash mismatch')
    records = {}
    with (run/'details/raw_frames.jsonl').open(encoding='utf-8') as stream:
        for line in stream:
            r = json.loads(line)
            if r['frame_index'] in FRAMES:
                if r['frame_index'] in records: raise ValueError('Duplicate frame')
                records[r['frame_index']] = r
    if set(records) != set(FRAMES): raise ValueError('Missing diagnostic frame')
    started = time.perf_counter(); cpu = time.process_time()
    from pilot_metrics import memory
    normalize = input_transforms()[2]
    log = args.output_dir/f'threads_{args.worker_threads}.jsonl'
    with log.open('x', encoding='utf-8') as stream:
        def emit(row):
            stream.write(json.dumps(row, allow_nan=False)+'\n')
            stream.flush(); os.fsync(stream.fileno())
        tensors = {}
        for index in FRAMES:
            r = records[index]
            relative = Path(r['input_image'])
            if relative.is_absolute() or '..' in relative.parts: raise ValueError('Unsafe input reference')
            image_path = (run/relative).resolve()
            if run not in image_path.parents: raise ValueError('Input outside recorded run')
            with Image.open(image_path) as image:
                if image.mode != 'RGB' or image.size != (224, 224):
                    raise ValueError('Expected audited RGB 224 input')
                # Resize/CenterCrop were already applied to this saved input.
                # Reuse official normalization, without cropping the audited image twice.
                if hashlib.sha256(image.tobytes()).hexdigest() != r['input_rgb_sha256']:
                    raise ValueError('Audited RGB hash mismatch')
                tensor = normalize(image)
            if hashlib.sha256(tensor.numpy().tobytes()).hexdigest() != r['normalized_tensor_sha256']:
                raise ValueError('Normalized tensor hash mismatch')
            tensors[index] = tensor
        started = time.perf_counter(); cpu = time.process_time()
        runtime = OfficialRuntime(args.official_source, args.weights, args.worker_threads)
        emit(dict(kind='runtime', environment=runtime.environment,
                  load_wall_s=time.perf_counter()-started,
                  load_cpu_s=time.process_time()-cpu))
        for warmup, index in [(True, FRAMES[0])] + [(False, i) for i in FRAMES]:
            wall = time.perf_counter(); cpu = time.process_time()
            prediction = runtime.predict(tensors[index])
            matrix=prediction['rotation_matrix']; original=records[index]['rotation_matrix']
            original_delta=max(abs(matrix[a][b]-original[a][b]) for a in range(3) for b in range(3))
            emit(dict(kind='prediction', frame_index=index, warmup=warmup,
                      prediction_wall_s=time.perf_counter()-wall,
                      prediction_cpu_s=time.process_time()-cpu,
                      recorded_matrix_max_difference=original_delta,
                      recorded_matrix_within_tolerance=original_delta <= 1e-6,
                      **prediction, memory=memory()))

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inspect-cpu', action='store_true')
    parser.add_argument('--recorded-run', type=Path)
    parser.add_argument('--weights', type=Path)
    parser.add_argument('--official-source', type=Path)
    parser.add_argument('--output-dir', type=Path)
    parser.add_argument('--worker-threads', type=int, choices=(1, 2, 4), help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.inspect_cpu:
        print(json.dumps(cpu_info(), indent=2)); return
    if not all((args.recorded_run, args.weights, args.official_source, args.output_dir)):
        parser.error('recorded-run, weights, official-source and output-dir are required')
    if args.worker_threads:
        worker(args); return
    out = args.output_dir.resolve(); repo = Path(__file__).resolve().parents[2]
    if out == repo or repo in out.parents: parser.error('Use a new output directory outside checkout')
    out.mkdir(parents=True, exist_ok=False)
    report = dict(status='running', frames=FRAMES, order=[4, 1, 2],
                  total_limit_s=180, cleanup_grace_s=5, interop_threads=4,
                  matrix_element_tolerance=1e-6, cpu_before=cpu_info(), conditions=[])
    save(out/'report.json', report)
    start = time.monotonic()
    for threads in report['order']:
        remaining = 180-(time.monotonic()-start)
        if remaining <= 0: report['status']='interrupted'; break
        command = [sys.executable, '-B', str(Path(__file__).resolve()),
                   '--recorded-run', str(args.recorded_run.resolve()),
                   '--weights', str(args.weights.resolve()),
                   '--official-source', str(args.official_source.resolve()),
                   '--output-dir', str(out), '--worker-threads', str(threads)]
        with (out/f'threads_{threads}.log').open('x', encoding='utf-8') as log:
            child = subprocess.Popen(command, stdout=log, stderr=log)
            try: code = child.wait(timeout=remaining)
            except (subprocess.TimeoutExpired, KeyboardInterrupt):
                child.kill(); child.wait(timeout=5)
                report['status']='interrupted'; code=None
        report['conditions'].append(dict(threads=threads, exit_code=code))
        save(out/'report.json', report)
        if code != 0:
            if report['status'] != 'interrupted': report['status']='failed'
            break
    else: report['status']='completed'
    report['elapsed_s']=time.monotonic()-start
    report['cpu_after']=cpu_info()
    # Compare all available measured matrices; retain partial records and failures.
    reference = {}
    differences = []
    for threads in report['order']:
        file = out/f'threads_{threads}.jsonl'
        if not file.exists(): continue
        for line in file.read_text().splitlines():
            try: row=json.loads(line)
            except json.JSONDecodeError: continue
            if row.get('kind') != 'prediction' or row['warmup']: continue
            i=row['frame_index']; m=row['rotation_matrix']
            if i not in reference: reference[i]=m
            delta=max(abs(m[a][b]-reference[i][a][b]) for a in range(3) for b in range(3))
            differences.append(dict(threads=threads, frame_index=i, max_element_difference=delta,
                                    within_tolerance=delta <= 1e-6))
    report['matrix_comparisons']=differences
    save(out/'report.json', report)
    print(json.dumps(dict(status=report['status'], elapsed_s=report['elapsed_s'])))

if __name__ == '__main__': main()
