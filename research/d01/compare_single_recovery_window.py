"""Offline comparison using recorded detections only; never loads models."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
from single_recovery_window import select


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--archive-root', type=Path, required=True)
    p.add_argument('--output-dir', type=Path, required=True)
    a = p.parse_args()
    a.output_dir.mkdir(parents=True, exist_ok=False)
    root = a.archive_root
    baseline = root/'auto_gap_onnx_20261108T163900/rule.py'
    spec = importlib.util.spec_from_file_location('frozen_baseline', baseline)
    old = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(old)
    cases = dict(holdout=root/'holdout_fixed_rule_20261108T172939/fresh_fast',
                 labelled=root/'auto_gap_onnx_20261108T163900/labelled/fresh_fast',
                 toddler=root/'auto_gap_onnx_20261108T163900/toddler/fresh_fast')
    results = {}
    for name, folder in cases.items():
        paths = [folder/'details'/f for f in ('frames.jsonl', 'raw.json', 'ema_050.json')]
        before = {str(f): hashlib.sha256(f.read_bytes()).hexdigest() for f in paths}
        rows = [json.loads(s) for s in paths[0].read_text().splitlines() if s.strip()]
        detections = {mode: json.loads(path.read_text()) for mode, path in zip(('raw', 'ema_050'), paths[1:])}
        original = old.select(rows, detections, 24)
        variant = select(rows, detections, 24)
        assert before == {str(f): hashlib.sha256(f.read_bytes()).hexdigest() for f in paths}
        results[name] = dict(old=original, variant=variant, source_sha256=before)
        print(name, 'old=', original['selected'], 'new=', variant['selected'])
    (a.output_dir/'comparison.json').write_text(json.dumps(results, indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
