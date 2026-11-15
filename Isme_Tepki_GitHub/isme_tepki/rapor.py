"""Yerel HTML/video raporu ve disari aktarilabilir bas acisi grafigi."""
import csv
from html import escape
from pathlib import Path
import warnings

import numpy as np
from scipy.spatial.transform import Rotation


def angles(rows):
    values = np.full((len(rows), 3), np.nan)
    with warnings.catch_warnings():
        warnings.simplefilter('ignore', UserWarning)
        for i, row in enumerate(rows):
            if row['valid']:
                # Rz Ry Rx: pitch X, yaw Y, roll Z. Euler sicramasi hareket sayilmaz.
                z, y, x = Rotation.from_matrix(row['rotation_matrix']).as_euler('ZYX', degrees=True)
                values[i] = x, y, z
    return values


def fmt(value):
    return 'Belirsiz' if value is None else '%.3f' % value


def comparison_html(comparison):
    if not comparison:
        return ''
    status_names = dict(matched='Uyumlu', mismatch='Zaman / yön uyuşmazlığı', missed='Kaçırılan',
                        extra='Fazladan tespit', uncertain='Belirsiz')
    text = ['<section><h2>Manuel etiket karşılaştırması</h2>',
            '<p class="indicator %s">%s</p>' % (comparison['indicator'], escape(comparison['indicator_label'])),
            '<p>Bu gösterge etiketlerle algoritmanın uyumunu ve değerlendirme yeterliliğini anlatır; '
            'çocuğun gelişimsel durumunu göstermez. Ana yöntem: EMA 0.50.</p>',
            '<p>İnceleyen: %s. Eksiksiz incelenen süre: %s sn.</p>' %
            (escape(comparison.get('reviewer') or 'Henüz belirtilmedi'), fmt(comparison['reviewed_duration_s']))]
    for method in ('ema_050', 'raw', 'ema_025'):
        summary = comparison['methods'][method]
        text.append('<details%s><summary>%s — %s</summary>' %
                    (' open' if method == 'ema_050' else '', escape(method), escape(summary['label'])))
        text.append('<p>' + ' · '.join('%s: %s' % (name, summary['counts'][key])
                                     for key, name in status_names.items()) + '</p>')
        text.append('<p>Yön etiketi: %s hareket; yön kararıyla karşılaştırılabilen: %s.</p>' %
                    (summary['direction_labeled'], summary['direction_compared']))
        text.extend('<p>%s</p>' % escape(message) for message in summary['messages'])
        if summary['records']:
            text.append('<div class="scroll"><table><thead><tr><th>Manuel / algoritma</th><th>Sonuç</th>'
                        '<th>Gözlenen bulgu</th><th>Olası açıklama — doğrulanmadı</th></tr></thead><tbody>')
            for record in summary['records']:
                facts = '<br>'.join(escape(f) for f in record['facts'])
                if record['reviewer_note']:
                    facts += '<br><b>İnsan notu:</b> ' + escape(record['reviewer_note'])
                text.append('<tr><td>%s / %s</td><td>%s</td><td>%s</td><td>%s</td></tr>' %
                            (escape(record['manual_id'] or '—'), escape(record['candidate_id'] or '—'),
                             status_names[record['status']], facts,
                             '<br>'.join(escape(f) for f in record['possible_causes']) or '—'))
            text.append('</tbody></table></div>')
        text.append('</details>')
    rules = comparison['rules']
    text.append('<details><summary>Renk ve eşleştirme kuralları</summary>'
                '<p>Yeşil: video tamamen incelenmiş, ölçüm yeterli ve etiketlerle uyuşmazlık yok. '
                'Sarı: etiket/kapsam/ölçüm/başlangıç/bitiş veya gerekli yön kararı eksik. '
                'Kırmızı: değerlendirilebilen etiketlerde kaçırma, fazladan tespit veya tolerans dışı zaman/yön farkı var. '
                'Uyuşmazlık varsa kırmızı önceliklidir; veri eksiklikleri ayrıca yazılır.</p>'
                '<p>Eşleştirme bire birdir. Başlangıç farkı en fazla %s sn; ayrıca zaman aralıkları kesişmeli '
                'veya başlangıç farkı %s sn içinde olmalıdır. Önce en çok eşleşme, sonra en küçük başlangıç farkı seçilir. '
                'Kabul edilen başlangıç/bitiş farkı ±%s sn. Asgari yerel ölçüm kapsaması %s; '
                'en uzun ölçüm boşluğu %s sn. Bunlar doğrulanmış doğruluk eşikleri değil, açık mühendislik kurallarıdır.</p>' %
                (fmt(rules['match_start_limit_s']), fmt(rules['time_tolerance_s']),
                 fmt(rules['time_tolerance_s']), '%%%g' % (rules['min_coverage'] * 100), fmt(rules['max_gap_s'])))
    text.append('<p>%s</p></details><p><a href="karsilastirma.json">Karşılaştırma JSON</a> · '
                '<a href="hatalar.csv">Hata ve karşılaştırma CSV</a></p></section>' % escape(comparison['note']))
    labels_file = 'etiketler_kullanilan.json' if comparison['labels_present'] else 'etiketler_sablon.json'
    text.insert(-1, '<p><a href="%s">%s</a></p>' % (labels_file,
                'Kullanılan insan etiketleri' if comparison['labels_present'] else 'Bu video için boş etiket şablonu'))
    return ''.join(text)


def render(out, result, methods, detections, gaze, flow_samples=None):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    colors = {'raw': '#7c838a', 'ema_050': '#176c9c', 'ema_025': '#a66b12'}
    labels = {'raw': 'Ham', 'ema_050': 'EMA 0.50 (ana)', 'ema_025': 'EMA 0.25 (deney)'}
    flow = result.get('optical_flow')
    fig, axes = plt.subplots(5 if flow else 4, 1, figsize=(13, 12 if flow else 10), sharex=True)
    with (out / 'acilar.csv').open('w', encoding='utf-8-sig', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['method', 'frame', 'time_s', 'valid', 'pitch_deg', 'yaw_deg', 'roll_deg', 'median_speed_deg_s'])
        for method, rows in methods.items():
            values = angles(rows)
            times = [r['time_s'] if r['time_s'] is not None else np.nan for r in rows]
            features = detections[method]['feature_records']
            speeds = [r['median_speed_deg_s'] for r in features]
            for r, a, speed in zip(rows, values, speeds):
                writer.writerow([method, r['frame_index'], r['time_s'], r['valid'],
                                 *[None if not np.isfinite(v) else float(v) for v in a], speed])
            for j, ax in enumerate(axes[:3]):
                # Euler sarilmasi ve zaman/kare kopukluklari uzerinden cizgi gecirme.
                xplot, yplot = [], []
                for i, (t, value) in enumerate(zip(times, values[:, j])):
                    gap = i > 0 and (rows[i]['frame_index'] != rows[i - 1]['frame_index'] + 1 or
                          not np.isfinite(times[i - 1]) or not np.isfinite(t) or
                          t - times[i - 1] > 1.5 / result['video']['fps'] or
                          abs(value - values[i - 1, j]) > 180)
                    if gap:
                        xplot.append(np.nan); yplot.append(np.nan)
                    xplot.append(t); yplot.append(value)
                ax.plot(xplot, yplot, color=colors[method], label=labels[method], linewidth=1)
            axes[3].plot(times, [np.nan if v is None else v for v in speeds],
                         color=colors[method], label=labels[method], linewidth=1)
    for ax, name in zip(axes, ['Pitch / yukari-asagi (derece)', 'Yaw / saga-sola (derece)',
                               'Roll / yana egilme (derece)', 'Medyan acisal hiz (derece/sn)']):
        ax.set_ylabel(name)
        ax.grid(alpha=.2)
        for i, event in enumerate(result['calls']):
            call = event['call']
            ax.axvspan(call['start_s'], call['end_s'], color='black', alpha=.09,
                       label='Seslenme araligi' if i == 0 else None)
        ax.legend(loc='upper right', fontsize=8, ncol=2)
    for i, candidate in enumerate(detections['ema_050']['candidates']):
        for key, style, label in [('start_s', '-', 'Ana hareket baslangici'),
                                  ('end_s', '--', 'Ana hareket bitisi'),
                                  ('start_confirmed_s', ':', 'Baslangic dogrulamasi'),
                                  ('end_confirmed_s', ':', 'Bitis dogrulamasi')]:
            t = candidate.get(key)
            if t is not None:
                axes[3].axvline(t, color=colors['ema_050'], linestyle=style,
                               alpha=.7, label=label if i == 0 else None)
    setting = detections['ema_050']['setting']
    axes[3].axhline(setting['start_deg_s'], color='black', linestyle='--', linewidth=.7, label='Baslama esigi')
    axes[3].axhline(setting['stop_deg_s'], color='black', linestyle=':', linewidth=.7, label='Durma esigi')
    axes[3].legend(fontsize=7, ncol=3, loc='upper right')
    if flow:
        ax = axes[4]
        times = [s['time_s'] if s['time_s'] is not None else np.nan for s in flow_samples]
        speeds = [s['speed'] if s['speed'] is not None else np.nan for s in flow_samples]
        ax.plot(times, speeds, color='#375b43', linewidth=1, label='Baş bölgesinde optik akış')
        ax.axhline(flow['parameters']['start_speed'], color='black', linestyle='--', label='Başlama eşiği')
        ax.axhline(flow['parameters']['stop_speed'], color='black', linestyle=':', label='Durma eşiği')
        for index, stop in enumerate(flow['stops']):
            ax.axvline(stop['time_s'], color='#375b43', label='Durdu' if index == 0 else None)
            ax.axvline(stop['confirmed_s'], color='#375b43', linestyle=':',
                       label='Durma doğrulaması' if index == 0 else None)
        for event in result['calls']:
            call = event['call']
            ax.axvspan(call['start_s'], call['end_s'], color='black', alpha=.09)
        ax.set_ylabel('Baş köşegeni/sn')
        ax.grid(alpha=.2)
        ax.legend(fontsize=7, ncol=3, loc='upper right')
    axes[-1].set_xlabel('Video zamani (saniye)')
    fig.suptitle('Bas acilari ve hareket adaylari | 24 FPS | ham / SO(3) EMA karsilastirmasi')
    fig.text(.01, .005, 'Kaynak: %s | Euler sarilma cizgileri kesilir; hareket hizlari donme matrislerinden hesaplanir.' %
             Path(result['video']['path']).name, fontsize=8)
    fig.tight_layout(rect=(0, .025, 1, .96))
    fig.savefig(out / 'bas_acilari.png', dpi=150)
    plt.close(fig)

    def button(t):
        return '<button data-time="%s">%s sn</button>' % (t, fmt(t)) if t is not None else 'Belirsiz'

    def event_times(e):
        return '%s · doğrulama %s' % (button(e['time_s']), button(e['confirmed_s']))

    def return_description(returned):
        if returned['events']:
            return '<br>'.join('%s · Pozdan ayrılma %s' % (event_times(item), button(item['departure_s']))
                               for item in returned['events'])
        return {'unknown_baseline': 'Başlangıç pozu için yeterli ölçüm yok',
                'unstable_baseline': 'Çağrı öncesi baş pozu sabit değildi',
                'unconfirmed': 'Başlangıç pozuna dönüş doğrulanmadı'}[returned['status']]

    pose_html = ''
    pose = result.get('head_pose')
    if pose:
        device_label = ''
        if pose.get('device_name'):
            device_label = '<p>%s · %s</p>' % (escape(pose['device'].upper()), escape(pose['device_name']))
        coverage = ''.join('<li>%s · %s/%s kare · Önceki ölçümün boş olduğu %s karede poz var</li>' %
                           (escape(values['label']), values['valid_frames'], result['frame_count'],
                            values['recovered_frames']) for values in pose['methods'].values())
        pose_html = ('<section><h2>Baş pozu kapsaması</h2>%s<ul>%s</ul>'
                     '<p><a href="bas_pozu.csv">Kare bazında poz, baş kutusu ve ölçüm durumu</a></p></section>' %
                     (device_label, coverage))

    flow_html = ''
    if flow:
        stops = ''.join('<li>%s</li>' % event_times(s) for s in flow['stops'])
        flow_html = ('<section><h2>Optik akış deneyi</h2><p>Geçerli ölçüm: %s ardışık kare çifti. '
                     '<a href="optik_akis.csv">Kare bazında hız ve takip kalitesi</a></p>' % flow['usable_pairs'])
        flow_html += ('<p>Klipteki durma adayları</p><ul>%s</ul>' % stops if stops else
                      '<p>Klipte doğrulanmış durma adayı yok.</p>')
        flow_html += '</section>'

    events_html = []
    for event in result['calls']:
        call = event['call']
        pieces = ['<section><h2>%s — %s</h2>' % (escape(call['id']), escape(call.get('name', 'İsim'))),
                  '<p>Seslenme: %s – %s. Kaynak: <b>%s</b>.</p>' %
                  (button(call['start_s']), button(call['end_s']), escape(call['timing_source'])),
                  '<p>Gözlem sonu: %s sn. %s</p>' % (fmt(event['observation_end_s']),
                  'Tanımlı pencere tamamlandı.' if event['observation_complete'] else 'Klip tanımlı gözlem penceresi bitmeden sona eriyor.')]
        alignment = call.get('speaker_alignment')
        if alignment:
            label = alignment['label']
            if alignment.get('target_id'):
                label += ' (%s)' % alignment['target_id']
            pieces.append('<p><b>Çağıran kişi</b> · %s</p>' % escape(label))
        if flow:
            experiment = event['optical_flow']
            look, stop, returned = (experiment[key] for key in ('look', 'stop', 'return_to_baseline'))
            pieces.append('<h3>Deneysel olaylar</h3><dl><dt>Baktı</dt><dd>%s</dd><dt>Durdu</dt>' %
                          (event_times(look) if look['status'] == 'observed' else escape(look['label'])))
            for item in stop['events']:
                relation = 'Çağrı sonrası başlayan hareket' if item['relation'] == 'after_call' else 'Hareket çağrı öncesinde başlamış veya başlangıcı belirsiz'
                pieces.append('<dd>%s · %s</dd>' % (event_times(item), relation))
            if not stop['events']:
                pieces.append('<dd>%s</dd>' % ('Geçerli optik akış ölçümü yok' if stop['status'] == 'no_flow_data'
                              else 'Doğrulanmış durma adayı yok'))
            method = experiment.get('return_pose_method')
            title = 'Geri döndü' if method is None else 'Geri döndü · ' + pose['methods'][method]['label']
            pieces.append('<dt>%s</dt><dd>%s</dd></dl>' % (escape(title), return_description(returned)))
            if method is not None:
                comparisons = ''.join('<li>%s · %s</li>' % (escape(pose['methods'][name]['label']),
                                      return_description(value)) for name, value in
                                      experiment['return_comparison'].items() if name != method)
                pieces.append('<details><summary>Diğer poz yöntemleriyle dönüş karşılaştırması</summary><ul>%s</ul></details>' %
                              comparisons)
            for late in experiment.get('return_after_window', []):
                pieces.append('<p>Gözlem penceresi dışında dönüş adayı · %s</p>' % event_times(late))
        manual = call.get('manual_movement')
        if manual:
            pieces.append('<p>Manuel hareket işaretleri: %s – %s. Başlangıca göre manuel gecikme: %s sn. '
                          'Bu işaretler otomatik dedektöre verilmez; insan incelemesi kaydıdır.</p>' %
                          (button(manual.get('start_s')), button(manual.get('end_s')),
                           fmt(event['manual_latency_from_start_s'])))
        for method in ('ema_050', 'raw', 'ema_025'):
            pieces.append('<details%s><summary>%s</summary>' % (' open' if method == 'ema_050' else '', labels[method]))
            candidates = event['methods'][method]
            if not candidates:
                pieces.append('<p>Bu aralıkta doğrulanmış hareket adayı yok. Bu, tepki yok demek değildir.</p>')
            else:
                pieces.append('<div class="scroll"><table><thead><tr><th>Aday</th><th>Başlangıç / doğrulama</th>'
                              '<th>Bitiş / doğrulama</th><th>Gecikme: çağrı başlangıcı / bitişi</th><th>Yön</th></tr></thead><tbody>')
                for c in candidates:
                    relation = 'Çağrı sonrası aday' if c['relation'] == 'after_call_candidate' else 'Önceden başlamış / başlangıcı bilinmiyor'
                    pieces.append('<tr><td>%s<br>%s</td><td>%s<br>%s</td><td>%s<br>%s</td><td>%s / %s sn</td><td>%s</td></tr>' %
                        (escape(c['candidate_id']), relation, button(c['start_s']), button(c['start_confirmed_s']),
                         button(c['end_s']), button(c.get('end_confirmed_s')), fmt(c['latency_from_start_s']),
                         fmt(c['latency_from_end_s']), escape(c['direction']['label'])))
                    if manual:
                        pieces.append('<tr><td colspan="5">Algoritma − manuel sınır farkı: başlangıç %s sn; bitiş %s sn.</td></tr>' %
                                      (fmt(c['start_minus_manual_s']), fmt(c['end_minus_manual_s'])))
                pieces.append('</tbody></table></div>')
            pieces.append('</details>')
        pieces.append('</section>')
        events_html.append(''.join(pieces))
    if not result['calls']:
        events_html.append('<section><h2>Seslenme kaydı yok</h2><p>Baş açıları ve genel hareket adayları çıkarıldı; '
                           'isme göre gecikme hesaplanmadı. calls alanına zaman ekleyin veya ses taslağını inceleyin.</p></section>')
    limits = ''.join('<li>%s</li>' % escape(s) for s in result['limitations'])
    video_uri = escape(Path(result['video']['path']).as_uri(), quote=True)
    player_source = video_uri
    video_controls = ''
    if result.get('annotated_video'):
        player_source = escape(result['annotated_video']['filename'], quote=True)
        video_controls = ('<p class="video-options"><button type="button" data-source="%s" aria-pressed="true">'
                          'İşaretlenmiş video</button> <button type="button" data-source="%s" aria-pressed="false">'
                          'Orijinal video</button> <a href="%s">MP4 dosyasını aç</a></p>' %
                          (player_source, video_uri, player_source))
    html = '''<!doctype html><html lang="tr"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>İsme tepki analizi</title>
<style>body{font:16px/1.5 system-ui;background:#f6f7f8;color:#202b32;max-width:1200px;margin:24px auto;padding:0 20px}
h1{font-size:26px}h2{font-size:20px}section{background:white;padding:20px;margin:20px 0;border:1px solid #dce1e4}
video{width:100%;max-height:430px;background:#151b20}img{width:100%}table{width:100%;border-collapse:collapse;font-size:14px}
td,th{padding:12px 8px;border-bottom:1px solid #dce1e4;text-align:left;vertical-align:top}.scroll{overflow:auto}
button{border:1px solid #b4c3cc;border-radius:3px;background:white;padding:4px 8px;cursor:pointer;color:#176c9c}
.video-options button[aria-pressed="true"]{background:#176c9c;color:white}.video-options a{margin-left:10px}
.video-options + video{max-height:680px}
summary{cursor:pointer;font-weight:600;padding:10px 0}a{color:#176c9c}.muted{color:#53636d}
.indicator{font-weight:600;padding:12px;border-left:5px solid}.green{background:#edf7ef;border-color:#237744;color:#195a32}
.yellow{background:#fff8dd;border-color:#aa7a00;color:#705200}.red{background:#fff0ef;border-color:#b13c34;color:#8b2923}</style>
<h1>İsme tepki analizi</h1><p>Seslenme, baş hareketi ve yön uyumu ayrı değerlendirilir. Ana yöntem EMA 0.50;
ham ve EMA 0.25 sonuçları karşılaştırma içindir. Tek bir aday otomatik olarak tepki seçilmez.</p>
''' + video_controls + '<video id="video" controls preload="metadata" src="' + player_source + '''"></video>
<p class="muted">Zaman düğmelerine tıklayarak videoyu inceleyin. Rapor taşınırsa kaynak video yolu erişilebilir kalmalıdır.</p>
<section><h2>Baş açıları ve hareket sınırları</h2><p>Geçerli ölçüm: ''' + str(result['valid_frames']) + ' / ' + str(result['frame_count']) + ''' kare.
Gri bantlar seslenme aralıklarıdır. Başlangıç/bitiş çizgileri ana yönteme aittir; noktalı çizgiler daha sonra gelen doğrulama anlarıdır.</p>
<img src="bas_acilari.png" alt="Zamana göre pitch, yaw, roll ve medyan açısal hız grafikleri"></section>
''' + flow_html + pose_html + comparison_html(result.get('comparison')) + ''.join(events_html) + '<section><h2>Yorumlama sınırları</h2><ul>' + limits + '''</ul>
<p><a href="sonuc.json">Sonuç JSON</a> · <a href="hareketler.csv">Hareket CSV</a> ·
<a href="acilar.csv">Açı CSV</a> · <a href="adaylar.json">Tüm adaylar ve belirsiz aralıklar</a></p></section>
<script>
const video = document.getElementById('video');
const sources = document.querySelectorAll('[data-source]');
let pendingTime = null;
function seek(time) {
  if (video.readyState) video.currentTime = Math.min(time, video.duration);
  else pendingTime = time;
}
video.addEventListener('loadedmetadata', () => {
  if (pendingTime !== null) seek(pendingTime);
  pendingTime = null;
});
sources.forEach(button => button.onclick = () => {
  if (button.getAttribute('aria-pressed') === 'true') return;
  pendingTime = pendingTime ?? video.currentTime;
  video.src = button.dataset.source;
  sources.forEach(option => option.setAttribute('aria-pressed', String(option === button)));
});
document.querySelectorAll('[data-time]').forEach(button => button.onclick = () => {
  seek(Number(button.dataset.time));
  video.pause();
  video.scrollIntoView({behavior:'smooth',block:'center'});
});
</script></html>'''
    (out / 'rapor.html').write_text(html, encoding='utf-8')
