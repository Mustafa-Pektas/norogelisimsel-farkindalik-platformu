"""Insan incelemesi sonrasi bire bir eslestirme; dedektoru/etiketleri degistirmez."""
import csv
import math

import numpy as np
from scipy.optimize import linear_sum_assignment


DEFAULT_RULES = dict(time_tolerance_s=.20, match_start_limit_s=.75,
                     min_coverage=.80, max_gap_s=.25)
COLOR_LABELS = {'green': 'Yeşil — etiketlerle uyumlu',
                'yellow': 'Sarı — inceleme / veri gerekli',
                'red': 'Kırmızı — etiketlerle uyuşmazlık'}


def finite(value):
    return type(value) in (int, float) and math.isfinite(value) and value >= 0


def validate(labels, video_hash, duration, calls):
    if labels.get('video_sha256') != video_hash:
        raise ValueError('Manuel etiketler ve video SHA256 eslesmiyor.')
    if type(labels.get('reviewed')) is not bool:
        raise ValueError('Etiket dosyasinda reviewed true/false olmali.')
    if labels['reviewed'] and not str(labels.get('reviewer') or '').strip():
        raise ValueError('Incelenmis etikette reviewer belirtilmeli.')
    call_ids = {c['id'] for c in calls}
    ids = set()
    previous_end = 0
    for interval in labels.get('intervals', []):
        a, b = interval.get('start_s'), interval.get('end_s')
        if not finite(a) or not finite(b) or not previous_end <= a < b <= duration + 1e-5:
            raise ValueError('Etiket araliklari sirali, cakismayan ve video icinde olmali.')
        if type(interval.get('complete')) is not bool:
            raise ValueError('Aralikta complete true/false olmali.')
        previous_end = b
        last = a
        for movement in interval.get('movements', []):
            identity = movement.get('id')
            if not isinstance(identity, str) or not identity or identity in ids:
                raise ValueError('Manuel hareket id benzersiz olmali.')
            ids.add(identity)
            start, end = movement.get('start_s'), movement.get('end_s')
            if not finite(start) or not finite(end) or not last <= start < end <= b:
                raise ValueError('Manuel hareketler sirali, cakismayan ve kendi araliginda olmali.')
            last = end
            correct = movement.get('direction_correct')
            if correct is not None and type(correct) is not bool:
                raise ValueError('direction_correct yalniz true/false/null olabilir.')
            if movement.get('call_id') is not None and movement['call_id'] not in call_ids:
                raise ValueError('Manuel harekette call_id mevcut bir seslenmeye ait olmali.')
            if correct is not None and not movement.get('call_id'):
                raise ValueError('Yon etiketi icin call_id gerekir.')


def quality(rows, start, end, fps, rules):
    times = [r['time_s'] for r in rows if r['valid'] and r['time_s'] is not None
             and start <= r['time_s'] < end]
    expected = max(1, math.ceil((end - start) * fps - 1e-5))
    coverage = min(1.0, len(times) / expected)
    gaps = np.diff([start, *times, end])
    gap = max(0.0, float(max(gaps, default=end - start)) - 1 / fps)
    return dict(coverage=coverage, max_missing_gap_s=gap,
                sufficient=coverage + 1e-9 >= rules['min_coverage'] and gap <= rules['max_gap_s'] + 1e-9)


def match(manual, candidates, rules):
    """En cok bire bir eslesme; sonra en kucuk baslangic farki. Acik dummy sutunlar."""
    if not manual or not candidates:
        return []
    n, m = len(manual), len(candidates)
    penalty = n + 1.0
    cost = np.full((n, m + n), penalty)
    cost[:, :m] = 2 * penalty
    for i, label in enumerate(manual):
        for j, candidate in enumerate(candidates):
            start = candidate.get('start_s')
            if start is None:
                continue
            delta = abs(start - label['start_s'])
            finish = candidate.get('end_s')
            overlap = finish is None or (start < label['end_s'] and finish > label['start_s'])
            if delta <= rules['match_start_limit_s'] and (overlap or delta <= rules['time_tolerance_s']):
                cost[i, j] = delta / rules['match_start_limit_s']
    ii, jj = linear_sum_assignment(cost)
    return [(int(i), int(j)) for i, j in zip(ii, jj) if j < m and cost[i, j] < penalty]


def evaluate(labels, result, detections, rows, duration, overrides=None):
    rules = dict(DEFAULT_RULES)
    unknown = set(overrides or {}) - set(rules)
    if unknown:
        raise ValueError('Bilinmeyen karsilastirma kurali: ' + ', '.join(sorted(unknown)))
    rules.update(overrides or {})
    if (not all(finite(v) and v > 0 for v in rules.values()) or rules['min_coverage'] > 1 or
            rules['time_tolerance_s'] > rules['match_start_limit_s']):
        raise ValueError('Karsilastirma toleranslari gecersiz.')
    fps = result['video']['fps']
    if labels is not None:
        validate(labels, result['video']['sha256'], duration, [e['call'] for e in result['calls']])
    reviewed = labels is not None and labels['reviewed']
    windows = [w for w in (labels or {}).get('intervals', []) if w['complete']] if reviewed else []
    reviewed_s = sum(w['end_s'] - w['start_s'] for w in windows)
    full_review = bool(windows) and reviewed_s >= duration - 1e-5
    summaries = {}
    for method, detected in detections.items():
        records = []
        def add(status, label=None, candidate=None, facts=(), possible=(), **extra):
            facts = list(facts)
            if extra.get('quality'):
                q = extra['quality']
                facts.append('Yerel kapsama: %%%.1f; en uzun ölçüm boşluğu: %.3f sn.' %
                             (100 * q['coverage'], q['max_missing_gap_s']))
            records.append(dict(status=status, manual_id=label['id'] if label else None,
                candidate_id=candidate['candidate_id'] if candidate else None,
                reviewer_note=str(label.get('notes', '')) if label else '',
                facts=facts, possible_causes=list(possible), **extra))
        for window in windows:
            a, b = window['start_s'], window['end_s']
            manual = window.get('movements', [])
            selected = []
            unknown_start = []
            for c in detected['candidates']:
                first = c.get('start_s')
                visible_first = first if first is not None else c.get('first_high_evidence_s')
                last = c.get('end_s')
                supported_end = last if last is not None else c.get('last_supported_time_s', duration)
                if visible_first is None or visible_first >= b or supported_end < a:
                    continue
                if first is None or first < a:
                    unknown_start.append((visible_first, supported_end))
                    add('uncertain', candidate=c, facts=['Adayın başlangıcı bilinmiyor veya incelenen aralığın dışında.'])
                else:
                    selected.append(c)
            pairs = match(manual, selected, rules)
            used_manual = {i for i, _ in pairs}
            used_candidates = {j for _, j in pairs}
            for i, j in pairs:
                label, c = manual[i], selected[j]
                start_diff = c['start_s'] - label['start_s']
                end = c.get('end_s')
                end_diff = end - label['end_s'] if end is not None and end <= b else None
                timing_error = abs(start_diff) > rules['time_tolerance_s'] + 1e-9 or (
                    end_diff is not None and abs(end_diff) > rules['time_tolerance_s'] + 1e-9)
                expected_direction = label.get('direction_correct')
                predicted_direction = None
                if label.get('call_id'):
                    event = next(e for e in result['calls'] if e['call']['id'] == label['call_id'])
                    candidate_result = next((r for r in event['methods'][method]
                                             if r['candidate_id'] == c['candidate_id']), None)
                    if candidate_result:
                        predicted_direction = candidate_result['direction']['correct']
                direction_error = expected_direction is not None and predicted_direction is not None and expected_direction != predicted_direction
                q = quality(rows, label['start_s'], label['end_s'], fps, rules)
                incomplete = end_diff is None or (expected_direction is not None and predicted_direction is None) or not q['sufficient']
                facts = ['Başlangıç farkı: %+.3f sn.' % start_diff,
                         'Bitiş farkı: %+.3f sn.' % end_diff if end_diff is not None else 'Algoritma bitişi değerlendirilemiyor.']
                if direction_error:
                    facts.append('Yön kararı manuel etiketle uyuşmuyor.')
                if expected_direction is not None and predicted_direction is None:
                    facts.append('Manuel yön etiketi var; algoritmanın yön kararı belirsiz.')
                if not q['sufficient']:
                    facts.append('Hareket aralığındaki baş ölçümü yetersiz.')
                possible = []
                if timing_error:
                    possible.append('Filtre/eşik gecikmesi veya hareketlerin birleşmesi olası; videoyla doğrulanmalı.')
                if direction_error:
                    possible.append('Hedef tahmini, konuşmacı eşleşmesi veya manuel yön etiketi incelenmeli.')
                add('mismatch' if timing_error or direction_error else 'uncertain' if incomplete else 'matched',
                    label, c, facts, possible, start_diff_s=start_diff, end_diff_s=end_diff,
                    timing_error=timing_error, direction_error=direction_error, quality=q,
                    expected_direction=expected_direction, predicted_direction=predicted_direction)
            for i, label in enumerate(manual):
                if i in used_manual:
                    continue
                q = quality(rows, label['start_s'], label['end_s'], fps, rules)
                ambiguous_overlap = any(start < label['end_s'] and end > label['start_s']
                                        for start, end in unknown_start)
                certain = q['sufficient'] and not ambiguous_overlap
                add('missed' if certain else 'uncertain', label=label, quality=q,
                    facts=['Manuel hareket için kurallara uyan algoritma adayı bulunamadı.',
                           'Yerel ölçüm yeterli.' if certain else 'Ölçüm veya çakışan adayın başlangıcı belirsiz; kaçırma diye sayılmadı.'],
                    possible=['Kısa hareketin eşik altında kalması, birleşmiş aday veya poz tahmin hatası olası; videoyla doğrulanmalı.'])
            for j, c in enumerate(selected):
                if j in used_candidates:
                    continue
                end = c.get('end_s')
                complete = end is not None and end <= b
                q = quality(rows, c['start_s'], min(end if end is not None else b, b), fps, rules)
                add('extra' if complete and q['sufficient'] else 'uncertain', candidate=c, quality=q,
                    facts=['Algoritma adayı için kurallara uyan manuel hareket bulunamadı.',
                           'İncelenen aralıkta bitiş ve ölçüm yeterli.' if complete and q['sufficient']
                           else 'Bitiş veya ölçüm yetersiz; fazladan tespit diye sayılmadı.'],
                    possible=['Poz titreşimi, fazla bölünmüş hareket veya manuel etiket farkı olası; videoyla doğrulanmalı.'])
        counts = {status: sum(r['status'] == status for r in records)
                  for status in ('matched', 'mismatch', 'missed', 'extra', 'uncertain')}
        associated = sum(r['manual_id'] is not None and r['candidate_id'] is not None for r in records)
        good_quality = all(quality(rows, w['start_s'], w['end_s'], fps, rules)['sufficient'] for w in windows)
        messages = []
        if not reviewed:
            messages.append('İnsan tarafından incelenmiş etiket dosyası yok.')
        if not full_review:
            messages.append('Videonun tamamı eksiksiz etiketlenmiş değil; yalnız complete=true aralıklar karşılaştırıldı.')
        if windows and not good_quality:
            messages.append('İncelenen aralıklarda ölçüm kaybı var.')
        if counts['uncertain']:
            messages.append('Kesin değerlendirilemeyen hareketler var.')
        if counts['mismatch'] or counts['missed'] or counts['extra']:
            color = 'red'
        elif not full_review or not good_quality or counts['uncertain']:
            color = 'yellow'
        else:
            color = 'green'
        summaries[method] = dict(color=color, label=COLOR_LABELS[color], counts=counts,
            paired_count=associated, timing_errors=sum(bool(r.get('timing_error')) for r in records),
            direction_errors=sum(bool(r.get('direction_error')) for r in records),
            direction_compared=sum(r.get('expected_direction') is not None and r.get('predicted_direction') is not None for r in records),
            direction_labeled=sum(m.get('direction_correct') is not None for w in windows for m in w.get('movements', [])),
            messages=messages, records=records)
    main = summaries[result['selected_method']]
    return dict(schema_version=1, scope='manual_label_agreement_not_child_development',
        rules=rules, rules_status='engineering_defaults_not_accuracy_validated',
        labels_present=labels is not None,
        reviewed=reviewed, reviewer=(labels or {}).get('reviewer'), reviewed_duration_s=reviewed_s,
        full_video_reviewed=full_review, indicator=main['color'], indicator_label=main['label'],
        main_method=result['selected_method'], methods=summaries,
        note='Kırmızı etiketle uyuşmazlığı, sarı eksik değerlendirmeyi, yeşil bu kurallarla uyumu gösterir. '
             'Yeşil yalnız etiketlenmiş özellikleri kapsar; yön etiketi yoksa yön doğruluğu sınanmış sayılmaz. '
             'Olası nedenler doğrulanmış kök neden değildir. Eşleşmiş aday doğru zaman veya doğru yön demek değildir.')


def export_csv(path, comparison):
    fields = ['method', 'status', 'manual_id', 'candidate_id', 'start_diff_s', 'end_diff_s',
              'timing_error', 'direction_error', 'expected_direction', 'predicted_direction',
              'coverage', 'max_missing_gap_s', 'reviewer_note', 'facts', 'possible_causes']
    with path.open('w', encoding='utf-8-sig', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        for method, summary in comparison['methods'].items():
            for record in summary['records']:
                row = {k: record.get(k) for k in fields}
                row.update(method=method, facts=' | '.join(record['facts']),
                           possible_causes=' | '.join(record['possible_causes']),
                           coverage=record.get('quality', {}).get('coverage'),
                           max_missing_gap_s=record.get('quality', {}).get('max_missing_gap_s'))
                writer.writerow(row)
