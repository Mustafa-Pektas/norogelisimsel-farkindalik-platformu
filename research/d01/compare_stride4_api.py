"""Compare two completed API checks; never starts an analysis or merges matrices."""
from pathlib import Path
import argparse,json


def compare(roots):
    entries=[];identity=None
    for root,engine in zip(roots,['mediapipe_pnp_flow','cascade_stride4_onnx']):
        accepted=json.loads((root/'acceptance.json').read_text())['runs']
        if len(accepted)!=1 or accepted[0]['status']!='completed':raise ValueError('One completed run per method required')
        run=accepted[0];result=json.loads((root/'api_result_0.json').read_text())
        job=json.loads((root/'jobs'/run['jobId']/'job.json').read_text())
        current=(result['videoHash'],job['targetPoint'])
        if identity is not None and identity!=current:raise ValueError('Different video or target selection')
        identity=current
        if result['source'].get('poseEngine','mediapipe_pnp_flow')!=engine:raise ValueError('Engine mismatch')
        if job.get('childExitCode')!=0 or not job.get('childClosedAt'):raise ValueError('Child not successfully closed')
        if any(result['manualTimes'][k]['time_s'] is not None for k in ['call_start_s','call_end_s']):
            raise ValueError('This comparison requires automatic call timing')
        entries.append(dict(engine=engine,videoHash=result['videoHash'],targetPoint=job['targetPoint'],
            coverage=result['coverage'],counts=result['counts'],callTiming=result.get('callTiming'),
            movements=result['movements'],engineCounts=result.get('engineCounts'),timings=result['timings'],
            apiUploadToResultS=run['upload_to_result_s'],mobileVisibleElapsedS=None,
            correctChildVisuallyVerified=None,trackingReview='Review saved frames.jsonl boxes against source video; not biometric identification'))
    return dict(schemaVersion='d01-stride4-api-comparison-1.0',runs=entries,
        limitations=['One video, one run per engine, fixed execution order; no general speed/quality ranking',
                     'New dynamic crop; not the previous fixed-ROI benchmark',
                     'Pose coverage is not pose accuracy or correct-target verification',
                     'API upload-to-result timing excludes mobile rendering; child and Python times overlap'])


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--mediapipe',type=Path,required=True);p.add_argument('--stride4',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    result=compare([a.mediapipe,a.stride4]);a.output.mkdir(parents=True,exist_ok=False)
    (a.output/'comparison.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    lines=['# D01 API candidate comparison','',
        '| Engine | Valid / total pose | API upload → result (s) | Python total (s) | 6D calls |',
        '|---|---:|---:|---:|---:|']
    for r in result['runs']:
        n=r['coverage'];calls=(r['engineCounts'] or {}).get('repnetCalls')
        lines.append(f"| {r['engine']} | {n['poseFrames']}/{n['totalFrames']} | {r['apiUploadToResultS']:.3f} | {r['timings']['total_s']:.3f} | {calls if calls is not None else 'unknown'} |")
    lines+=['','Correct child tracking still requires visual review. No mobile end-to-end measurement.',*result['limitations']]
    (a.output/'SUMMARY.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
