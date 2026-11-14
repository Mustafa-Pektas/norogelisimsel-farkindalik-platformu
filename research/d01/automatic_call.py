"""Local-only Turkish Deniz word timing. No speaker/response classification.

NFC/Turkish case/punctuation normalisation and exact word matching reused
from user-supplied Isme_Tepki.zip kod/audio_label_tool/audio_labels.py;
generator consumption/word_timestamps follows kod/isme_tepki/analiz.py.
Additional acceptance gates are fixed engineering checks, not calibration.
"""
from pathlib import Path
import math,re,time,unicodedata

STATUSES={'accepted','not_found','ambiguous','low_confidence','unavailable','failed'}


def normalize(text):
    text=unicodedata.normalize('NFC',text).replace('İ','i').replace('I','ı')
    return re.sub(r'[^\w]','',text.casefold())


def evaluate_words(segments,duration):
    matches=[]
    for segment in segments:
        for word in segment.words or []:
            if normalize(word.word)==normalize('Deniz'):
                matches.append((word,segment))
    result=dict(status='not_found',startS=None,endS=None,matchCount=len(matches),name='Deniz',language='tr')
    if not matches:return result
    if len(matches)!=1:return dict(result,status='ambiguous')
    w,s=matches[0]
    finite=lambda v:isinstance(v,(int,float)) and not isinstance(v,bool) and math.isfinite(v)
    # Conservative fixed ASR gates. Probability is NOT a behavioral confidence.
    if (not all(finite(v) for v in (w.start,w.end,w.probability,s.no_speech_prob,s.avg_logprob))
            or not 0<=w.start<w.end<=duration or not .80<=w.probability<=1
            or s.no_speech_prob>.50 or s.avg_logprob < -1.0):
        return dict(result,status='low_confidence')
    return dict(result,status='accepted',startS=float(w.start),endS=float(w.end))


def detect_call(video,model_path,duration,model_factory=None):
    begin=time.perf_counter();load_s=None;transcribe_s=None
    result=dict(status='unavailable',startS=None,endS=None,matchCount=None,name='Deniz',language='tr',code='audio_not_configured')
    try:
        path=None if model_path is None else Path(model_path)
        if path is None or not path.is_absolute() or not all((path/f).is_file() for f in ('model.bin','config.json','tokenizer.json')):
            return result
        if model_factory is None:
            try:from faster_whisper import WhisperModel
            except ImportError:
                result=dict(result,code='audio_dependency_missing')
                return result
            model_factory=WhisperModel
        t=time.perf_counter()
        model=model_factory(str(path),device='cpu',compute_type='int8',cpu_threads=4,local_files_only=True)
        load_s=time.perf_counter()-t;t=time.perf_counter()
        segments,_=model.transcribe(str(video),language='tr',task='transcribe',word_timestamps=True,
            vad_filter=True,condition_on_previous_text=False)
        result=evaluate_words(segments,duration)
        transcribe_s=time.perf_counter()-t
        return result
    except Exception:
        result=dict(status='failed',startS=None,endS=None,matchCount=None,name='Deniz',language='tr',code='audio_step_failed')
        return result
    finally:
        result['timings']=dict(total_s=time.perf_counter()-begin,model_load_s=load_s,transcribe_s=transcribe_s)


def effective_timing(audio,manual_start,manual_end):
    manual=manual_start is not None and manual_end is not None
    accepted=audio['status']=='accepted'
    return dict(schemaVersion='d01-call-timing-1.0',source='manual_user_input' if manual else 'automatic_word_timing' if accepted else 'unknown',
        startS=manual_start if manual else audio['startS'] if accepted else None,
        endS=manual_end if manual else audio['endS'] if accepted else None,
        audioStatus=audio['status'],matchCount=audio['matchCount'],name='Deniz',language='tr')
