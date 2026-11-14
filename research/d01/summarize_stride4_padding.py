"""Bounded summary of one real completed padding-v2 API check. No inference."""
from pathlib import Path
import argparse,csv,json


def summarize(root,out):
    accepted=json.loads((root/'acceptance.json').read_text())['runs']
    if len(accepted)!=1 or accepted[0]['status']!='completed':raise ValueError('One completed run required')
    record=accepted[0];job=root/'jobs'/record['jobId']
    state=json.loads((job/'job.json').read_text())
    result=json.loads((root/'api_result_0.json').read_text())
    params=json.loads((Path(__file__).parent/'parameters/stride4_deniz_acceptance.json').read_text())[0]
    if state['videoHash']!=params['sha256'] or state['targetPoint']!=params['targetPoint']:
        raise ValueError('Different Deniz video or targetPoint')
    if state.get('childExitCode')!=0 or not state.get('childClosedAt'):raise ValueError('Child not successfully closed')
    if result['source']['poseEngine']!='cascade_stride4_onnx':raise ValueError('Not Stride4')
    provenance=json.loads((job/'run/details/pose_engine.json').read_text())
    if provenance['cropRule']!='tracked-face-square-2x-centered-rgb128-pad-v2':raise ValueError('Padding v2 not used')
    if provenance.get('targetPolicy')!='bounded-flow-and-unique-reacquisition-v2':
        raise ValueError('Bounded flow and unique landmark reacquisition policy not used')
    rows=[json.loads(s) for s in (job/'run/details/frames.jsonl').read_text().splitlines()]
    calls=result['engineCounts']['repnetCalls']
    if type(calls) is not int or calls!=sum(r['repnet_calls_this_frame'] for r in rows):raise ValueError('6D call counter mismatch')
    if result['counts']['processed']!=len(rows) or result['counts']['valid']!=sum(r['valid'] for r in rows):
        raise ValueError('Counts mismatch')
    columns=['frame_index','time_s','crop_source_xywh','crop_status','crop_padding_ltrb_source_px',
        'rejection_reason','identity_status','valid','estimator_flag','repnet_calls_this_frame',
        'target_reacquired','reacquisition_time_s','reacquisition_gap_s','stride4_anchors_reset']
    columns+=['landmark_age_s','pose_target_basis']
    selected=[{k:r.get(k) for k in columns} for r in rows if 22<=r['frame_index']<=37]
    if len(selected)!=16:raise ValueError('Frames 22-37 incomplete')
    summary=dict(jobId=record['jobId'],videoHash=result['videoHash'],targetPoint=state['targetPoint'],
        counts=result['counts'],repnetCalls=calls,apiUploadToResultS=record['upload_to_result_s'],timings=result['timings'],
        frames22To37=selected,paddingRGB=provenance['paddingRGB'],
        frames24To83=[{k:r.get(k) for k in columns} for r in rows if 24<=r['frame_index']<=83],
        targetReacquisitions=[dict(frame_index=r['frame_index'],time_s=r['reacquisition_time_s'],
            gap_s=r['reacquisition_gap_s'],pose_valid=r['valid'],anchors_reset=r['stride4_anchors_reset'])
            for r in rows if r.get('target_reacquired')],
        limitation='Padding effect and correct identity require visual review; numerical validity is not pose accuracy')
    out.mkdir(parents=True,exist_ok=False)
    (out/'summary.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
    with (out/'frames_22_37.csv').open('w',newline='',encoding='utf-8') as stream:
        writer=csv.DictWriter(stream,fieldnames=columns);writer.writeheader();writer.writerows(selected)
    with (out/'frames_24_83.csv').open('w',newline='',encoding='utf-8') as stream:
        writer=csv.DictWriter(stream,fieldnames=columns);writer.writeheader();writer.writerows(summary['frames24To83'])
    print(json.dumps(dict(jobId=summary['jobId'],counts=summary['counts'],repnetCalls=calls,
        apiUploadToResultS=summary['apiUploadToResultS'],
        frames24To83=len(summary['frames24To83']),valid24To83=sum(r['valid'] for r in summary['frames24To83']),
        targetReacquisitions=summary['targetReacquisitions'],summaryFile=str(out/'summary.json')),indent=2))
    return summary


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--run',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True);a=p.parse_args();summarize(a.run,a.output)
