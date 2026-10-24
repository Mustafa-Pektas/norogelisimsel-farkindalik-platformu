const dns = require('dns');
dns.setDefaultResultOrder('ipv4first');

const express = require('express');
const cors = require('cors');
const dotenv = require('dotenv');
const multer = require('multer');
const path = require('path');
const { createHash, timingSafeEqual } = require('node:crypto');
const { GoogleGenerativeAI, SchemaType } = require('@google/generative-ai');
const { generateText, generateTextWithUsage } = require('./gemini_text');
const { createScenarioInputHandler, defaultCardsPath } = require('./scenario_input_generation');
const { createGenerationCapacity } = require('./generation_capacity');

function createApp({ env = process.env, generate = generateTextWithUsage, genAI: injectedGenAI, generationTimers,
  reportMeasurement } = {}) {
const mode = env.BACKEND_MODE || 'development';
if (!['development', 'deployment'].includes(mode)) {
  throw new Error('BACKEND_MODE development veya deployment olmalıdır.');
}
const deployment = mode === 'deployment';
const capacity = deployment ? createGenerationCapacity(env.GENERATION_MAX_CONCURRENT) : null;
let teamKeyHash;
if (deployment) {
  if (typeof env.TEAM_ACCESS_KEY !== 'string' || !/^[\x21-\x7e]+$/.test(env.TEAM_ACCESS_KEY)) {
    throw new Error('Deployment için TEAM_ACCESS_KEY boş olmayan, boşluksuz bir erişim anahtarı olmalıdır.');
  }
  teamKeyHash = createHash('sha256').update(env.TEAM_ACCESS_KEY).digest();
}

const app = express();

// Middleware
if (deployment) {
  // Ayrıştırıcı ve upload/sağlayıcı yollarından önce kapatılır.
  app.use((req, res, next) => {
    const allowed = (req.path === '/health' && ['GET', 'HEAD', 'OPTIONS'].includes(req.method)) ||
      (['/api/generate-scenario-input', '/api/generate-clip-plan', '/api/compare-scenario'].includes(req.path) &&
        ['POST', 'OPTIONS'].includes(req.method));
    if (!allowed) return res.status(404).json({ success: false, error: 'Endpoint bu çalışma modunda açık değil.' });
    next();
  });
}
app.use(cors());
if (deployment) {
  app.use((req, res, next) => {
    if (req.path === '/health' || req.method === 'OPTIONS') return next();
    const authorization = req.get('authorization');
    const match = typeof authorization === 'string' ? /^Bearer ([^\s]+)$/i.exec(authorization) : null;
    // Sabit boyutlu hash'ler: uzunluk farkında erken secret karşılaştırması yapılmaz.
    const received = createHash('sha256').update(match ? match[1] : '').digest();
    const valid = timingSafeEqual(teamKeyHash, received);
    if (!match || !valid) {
      res.set('WWW-Authenticate', 'Bearer');
      return res.status(401).json({ success: false, code: 'team_access_required',
        error: 'Ekip erişimi doğrulanamadı. Oturum erişim anahtarını kontrol edin.' });
    }
    next();
  });
}
app.use(express.json({ limit: deployment ? '1mb' : '50mb' }));
app.use(express.urlencoded({ extended: true, limit: deployment ? '1mb' : '50mb' }));

// Multer (Video yüklemeleri için bellekte tutucu)
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 100 * 1024 * 1024 }, // 100 MB maks
});

// Gemini İstemcisi
const rawKey = (env.GEMINI_API_KEY || '').trim();
const apiKey = rawKey.replace(/^["']|["']$/g, '').trim();
const hasApiKey = Boolean(apiKey && !apiKey.includes('BURAYA_GEMINI') && apiKey.length > 15);
const genAI = injectedGenAI ?? (hasApiKey ? new GoogleGenerativeAI(apiKey) : null);

// ==========================================
// 1. SAĞLIK KONTROLÜ (HEALTH CHECK)
// ==========================================
app.get('/health', (req, res) => {
  if (deployment) {
    return res.json({ status: 'online', service: 'Nörogelişimsel Farkındalık Platformu API',
      timestamp: new Date().toISOString() });
  }
  res.json({
    status: 'online',
    service: 'Nörogelişimsel Farkındalık Platformu API',
    geminiConfigured: hasApiKey,
    message: hasApiKey
      ? 'API anahtarı tanımlı; model erişimi ve çıktı doğruluğu henüz sınanmış sayılmaz.'
      : 'Üretim sağlayıcısı yapılandırılmadı.',
    timestamp: new Date().toISOString(),
  });
});

// ==========================================
// 2. 26 SAHNELİK VEO / ADOS-2 SENARYO MOTORU
// ==========================================
const SCENE_COUNT = 26;
const CLIP_SEC = 8;

// D01–D10 Standart Davranış Kataloğu (behavior_cards.dart ile %100 uyumlu)
const BEHAVIORS = {
  'D01': 'İsme tepki verme (Response to Name: İsmi söylendikten sonra yetişkine verilen yönelme ve sesli yanıt)',
  'D02': 'Yetişkinin işaret ettiği hedefe yönelme (Responding to Joint Attention: İşaret edilen nesneye dönüp bakma)',
  'D03': 'İstemek için işaret etme (Imperative Pointing: Ulaşamadığı oyuncağı istemek için işaret etme)',
  'D04': 'Hayali oyun — mış gibi yapma (Pretend Play: Boş fincanla bebeğe su içiriyormuş gibi yapma)',
  'D05': 'Paylaşmak için elindeki nesneyi gösterme (Showing Objects / Joint Attention: Oyuncağı göstererek ilgiyi paylaşma)',
  'D06': 'Basit motor hareketi taklit etme (Motor Imitation: Yetişkinin el çırpma veya bay-bay hareketini taklit etme)',
  'D07': 'Gülümsemeye karşılık verme (Shared Affect / Reciprocal Smile: Yetişkin gülümsedikten sonra tebessümle karşılık verme)',
  'D08': 'Jest desteği olmadan tek basamaklı sözel yönergeyi yerine getirme (Verbal Instruction: Sözel komutu anlama)',
  'D09': 'Nesneyi bir kaba yerleştirme (Object Placement: Bloğu kendiliğinden kutunun içine bırakma)',
  'D10': 'Kalemle kendiliğinden karalama yapma (Spontaneous Scribbling: Pastel boyayla kâğıtta çizgiler oluşturma)',
};

// Geriye dönük uyumluluk takma adı ve ONT eşlemesi
const ONTOLOGIES = {
  ...BEHAVIORS,
  'ONT-01': BEHAVIORS['D01'],
  'ONT-02': BEHAVIORS['D02'],
  'ONT-03': BEHAVIORS['D05'],
  'ONT-04': BEHAVIORS['D02'],
  'ONT-05': BEHAVIORS['D03'],
  'ONT-06': BEHAVIORS['D03'],
  'ONT-07': BEHAVIORS['D05'],
  'ONT-08': BEHAVIORS['D07'],
  'ONT-09': BEHAVIORS['D04'],
  'ONT-10': BEHAVIORS['D06'],
  'ONT-11': BEHAVIORS['D08'],
  'ONT-12': BEHAVIORS['D09'],
};

const RISK_PROFILES = {
  'TİPİK': 'Çağrıya 0-2 sn içinde bakış, sosyal gülümseme, göz teması, paylaşımlı oyun.',
  'ATİPİK': 'Çağrıya 3+ sn gecikme veya tepkisizlik, sınırlı göz teması, nesneye odaklı tekrarlayan oyun.',
  'SINIRDA': 'Tepkiler tutarsız: bazı denemelerde yanıt, bazılarında gecikme.',
};

// Sabit görünüm: model yazmaz, kod her prompt'un başına ekler
const CHARACTER =
  'Cinematic 35mm film still, locked-off stationary tripod at 45cm low child-eye level, f/2.8 aperture, soft 5500K diffused morning natural daylight. ' +
  'A photorealistic 24-month-old toddler with short brown hair, wearing a solid powder-blue crewneck cotton t-shirt and charcoal knit joggers, sitting barefoot on a Scandinavian light ash wooden floor with a navy-and-cream geometric wool rug. ' +
  'In the background, an adult female clinician in a beige knit sweater is seated quietly observing. ' +
  'Anatomically accurate hands with five distinct fingers, stable physics, no morphing, 4K photorealistic documentary realism.';

const scenarioSchema = {
  type: SchemaType.OBJECT,
  properties: {
    title: { type: SchemaType.STRING },
    summary: {
      type: SchemaType.STRING,
      description: 'Tüm 3,5 dakikayı baştan sona anlatan tek akıcı paragraf, Türkçe, 120-180 kelime, klinik terim yok',
    },
    scenes: {
      type: SchemaType.ARRAY,
      items: {
        type: SchemaType.OBJECT,
        properties: {
          phase: { type: SchemaType.STRING, enum: ['TABAN', 'UYARAN', 'KAPANIS'] },
          videoPrompt: { type: SchemaType.STRING, description: 'English. Visible behavior only. No clinical terms, no dialogue text.' },
          dialogue: { type: SchemaType.STRING, nullable: true },
          speaker: { type: SchemaType.STRING, enum: ['ADULT', 'CHILD'], nullable: true },
          startState: { type: SchemaType.STRING },
          endState: { type: SchemaType.STRING },
          clinical: {
            type: SchemaType.OBJECT,
            properties: {
              latencySeconds: { type: SchemaType.NUMBER, nullable: true },
              note: { type: SchemaType.STRING },
              atypical: { type: SchemaType.BOOLEAN },
            },
            required: ['note', 'atypical'],
          },
        },
        required: ['phase', 'videoPrompt', 'startState', 'endState', 'clinical'],
      },
    },
    assessment: {
      type: SchemaType.OBJECT,
      properties: {
        latencies: { type: SchemaType.ARRAY, items: { type: SchemaType.STRING } },
        atypicalCriteria: { type: SchemaType.ARRAY, items: { type: SchemaType.STRING } },
        score: { type: SchemaType.STRING },
        referralNote: { type: SchemaType.STRING },
      },
      required: ['latencies', 'atypicalCriteria', 'score', 'referralNote'],
    },
  },
  required: ['title', 'summary', 'scenes', 'assessment'],
};

function buildPrompts({ ageMonths, childName, ontologyCodes, riskProfile, materials, variation }) {
  const ontList = ontologyCodes.map((c) => `- ${c}: ${ONTOLOGIES[c] || c}`).join('\n');
  const riskKey = (riskProfile || 'ATİPİK').toUpperCase();

  const system = `Sen çocuk nörogelişimi (ADOS-2 Toddler / M-CHAT-R/F) ve Google Veo / Sora video üretim parametreleri konusunda uzmanlaşmış kıdemli bir klinik simülasyon ve görsel yönetmenisin.
Çıktın doğrudan Google Veo ile fotogerçekçi klinik eğitim videoları üretiminde kullanılacak. Videolarda sıfır bozulma (no morphing), kusursuz anatomi, sabit kamera açısı ve tam nörogelişimsel davranış doğruluğu şarttır.

Kurallar:
- "summary" alanına tüm 3.5 dakikalık senaryoyu anlatan, klinik olarak tutarlı, akıcı bir Türkçe özet yaz (120-180 kelime).
- Tam ${SCENE_COUNT} sahne üret. Fazlar sırayla: TABAN (6 sahne), UYARAN (11 sahne), KAPANIS (9 sahne).
- "videoPrompt": İngilizce yazılır. Yalnızca kamerada doğrudan görünen fiziksel mikrodavranışı, vücut postürünü, el/parmak hareketini, bakış yönünü (göz bebeği odağı), baş açısını (Yaw/Pitch) ve nesne manipülasyonunu yüksek detayla tarif et.
  * Tıbbi tanı kelimeleri ("autistic", "atypical", "delay") KULLANMA. Bunun yerine somut davranışı anlat ("keeps rolling the wheel forward, head stays stationary at Yaw 0°, eyes fixated on the spinning axle, ignoring the auditory stimulus").
  * Kamera hareket etmez (static locked tripod), lens açısı sabittir.
  * Her 8 saniyelik klipte net bir mikro zaman akışı belirt: "Seconds 0-4: ... Seconds 4-8: ..."
- "startState" ve "endState": Sahnenin ilk ve son karesindeki net fiziksel duruşu tarif et (Sahne N'in startState'i, Sahne N-1'in endState'i ile süreklilik sağlar).
- "dialogue": Varsa konuşulan cümle (en fazla 1 cümle). "speaker": 'ADULT' veya 'CHILD'.
- "clinical": note (Türkçe klinik gözlem ve ADOS-2 kriteri notu), latencySeconds (varsa tepki süresi sn cinsinden), atypical (boolean).
- summary ve clinical.note Türkçe, videoPrompt ve durumlar İngilizce yazılır.`;

  const user = `${ageMonths} aylık ${childName} için senaryo üret.
Hedef davranışlar:
${ontList}
Risk profili: ${riskKey} → ${RISK_PROFILES[riskKey] || RISK_PROFILES['ATİPİK']}
Materyal: ${materials}
Çeşitlilik tohumu: ${variation}`;

  return { system, user };
}

const mmss = (sec) => `${String(Math.floor(sec / 60)).padStart(2, '0')}:${String(sec % 60).padStart(2, '0')}`;

function validate(s) {
  const errors = [];
  if (!s.summary || s.summary.split(/\s+/).length < 40) errors.push('summary çok kısa');
  if (s.scenes.length !== SCENE_COUNT) errors.push(`sahne sayısı ${s.scenes.length}, olması gereken ${SCENE_COUNT}`);
  const order = { TABAN: 0, UYARAN: 1, KAPANIS: 2 };
  s.scenes.forEach((sc, i) => {
    if (i > 0 && order[sc.phase] < order[s.scenes[i - 1].phase]) errors.push(`sahne ${i + 1}: faz sırası bozuk`);
    if (sc.dialogue && !sc.speaker) errors.push(`sahne ${i + 1}: speaker eksik`);
    if (/autis|atypical|delay|diagnos/i.test(sc.videoPrompt)) errors.push(`sahne ${i + 1}: videoPrompt'ta klinik terim`);
    if (sc.videoPrompt.split(/\s+/).length > 250) errors.push(`sahne ${i + 1}: videoPrompt çok uzun`);
  });
  return errors;
}

// Zaman ve süreyi kod ekler
function finalize(s) {
  s.scenes = s.scenes.map((sc, i) => ({
    ...sc,
    id: i + 1,
    time: mmss(i * CLIP_SEC),
    durationSec: CLIP_SEC,
  }));
  return s;
}

// Veo'ya yapıştırılacak hazır prompt
function buildVeoPrompt(sc, name = 'the child') {
  const dlg = sc.dialogue
    ? ` ${sc.speaker === 'ADULT' ? 'The adult clinician' : 'The toddler'} says: "${sc.dialogue}"`
    : '';
  return `${CHARACTER} ${sc.videoPrompt}${dlg} Static medium shot at the child's eye level, natural light, realistic documentary style. No subtitles, no text overlay, 4K photorealistic, anatomically correct hands, solid object physics, no morphing.`;
}

async function generateOnce(genAI, modelName, prompts) {
  const raw = await generateText(genAI, modelName, prompts,
    { schema: scenarioSchema, maxOutputTokens: 16384 });
  return JSON.parse(raw);
}

// Anlatı girdisi üretir; 26 sahne endpoint'inden bağımsızdır, graf üretmez.
app.post('/api/generate-scenario-input', createScenarioInputHandler({
  capacity, reportMeasurement, ...(generationTimers ? { timers: generationTimers } : {}),
  generate: genAI ? (model, prompts, options) => generate(genAI, model, prompts, options) : null,
  modelName: (env.SCENARIO_INPUT_MODEL || '').trim(),
  cardsPath: env.BEHAVIOR_CARDS_PATH || defaultCardsPath,
}));

// Dalları/kimlikleri koruyan plan; doğrusal 26 sahne yolunu kullanmaz.
app.post('/api/generate-clip-plan', createScenarioInputHandler({
  capacity, reportMeasurement, ...(generationTimers ? { timers: generationTimers } : {}),
  clipPlan: true,
  generate: genAI ? (model, prompts, options) => generate(genAI, model, prompts, options) : null,
  modelName: (env.SCENARIO_INPUT_MODEL || '').trim(),
  cardsPath: env.BEHAVIOR_CARDS_PATH || defaultCardsPath,
}));

// Ekip A/B/C deneyi: aynı Bearer/gövde/kapasite/timeout sınırları; tek kol = en fazla bir çağrı.
app.post('/api/compare-scenario', createScenarioInputHandler({
  comparison: true, capacity, reportMeasurement, ...(generationTimers ? { timers: generationTimers } : {}),
  generate: genAI ? (model, prompts, options) => generate(genAI, model, prompts, options) : null,
  modelName: (env.SCENARIO_INPUT_MODEL || '').trim(),
  cardsPath: env.BEHAVIOR_CARDS_PATH || defaultCardsPath,
}));

app.post('/api/generate-scenario', async (req, res) => {
  try {
    const {
      ageMonths = 24,
      childName = 'Deniz',
      riskProfile = 'ATİPİK',
      ontologyCodes = [req.body.ontologyCode || req.body.behaviorCode || 'D01'],
      materials = 'Kırmızı ahşap araba ve kayın bloklar',
    } = req.body;

    console.log(`[*] Senaryo isteği: ${ageMonths} Ay, ${childName}, ${ontologyCodes.join('+')}, ${riskProfile}`);

    if (!hasApiKey || !genAI) {
      return res.status(400).json({ success: false, error: 'Gemini API anahtarı ayarlanmamış.' });
    }

    const variation = req.body.variation || Math.random().toString(36).slice(2, 8);
    const prompts = buildPrompts({ ageMonths, childName, ontologyCodes, riskProfile, materials, variation });
    const models = ['gemini-3.5-flash', 'gemini-3.1-flash-lite', 'gemini-3.5-flash-lite', 'gemini-3.8-flash'];
    let lastErr;

    for (const m of models) {
      for (let attempt = 0; attempt < 2; attempt++) {
        try {
          console.log(`[*] Model deneniyor: ${m} (deneme ${attempt + 1})...`);
          const raw = await generateOnce(genAI, m, prompts);
          const errors = validate(raw);
          if (errors.length) {
            lastErr = new Error(errors.join('; '));
            console.warn(`[!] ${m} doğrulama hatası:`, errors);
            continue;
          }
          const scenario = finalize(raw);
          scenario.scenes.forEach((sc) => {
            sc.veoPrompt = buildVeoPrompt(sc);
          });
          console.log(`[OK] Senaryo 26 sahne ile başarıyla üretildi (${m})!`);
          return res.json({
            success: true,
            model: m,
            scenario,
            metadata: { ageMonths, ontologyCodes, riskProfile, variation },
          });
        } catch (e) {
          console.warn(`[!] [${m}] hata:`, e.message);
          lastErr = e;
        }
      }
    }

    res.status(500).json({ success: false, error: lastErr?.message || 'Senaryo üretilemedi.' });
  } catch (error) {
    console.error('[!] API Hata:', error);
    res.status(500).json({ success: false, error: error.message || 'Sunucu hatası' });
  }
});

// ==========================================
// 3. VİDEO ANALİZİ (MULTIMODAL GEMINI VISION)
// ==========================================
app.post('/api/analyze-video', upload.single('video'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ success: false, error: 'Video dosyası bulunamadı.' });
    }

    console.log(`[*] Video analizi başlatıldı: ${req.file.originalname} (${(req.file.size / (1024 * 1024)).toFixed(2)} MB)`);

    if (!hasApiKey || !genAI) {
      return res.status(400).json({
        success: false,
        error: 'Gemini API anahtarı ayarlanmamış. Lütfen backend/.env dosyasını güncelleyin.',
      });
    }

    const prompt = `Sen ADOS-2 standartlarında çalışan bir çocuk nörogelişim video analiz uzmanısın.
Bu videodaki çocuğun davranışlarını incele:
1. İsme tepki (seslenildiğinde baş dönüyor mu, gecikme süresi kaç saniye?)
2. Göz teması ve sosyal gülümseme
3. Ortak dikkat (işaret edilen nesneye bakma)
4. Tekrarlayıcı veya atipik hareketler (tekerlek çevirme, el çırpma vb.)

Lütfen cevabını SADECE ve SADECE aşağıdaki JSON formatında ver (başka hiçbir metin veya markdown çiti ekleme):
{
  "summary": "Videonun genel klinik değerlendirme özeti.",
  "overallLevel": "green" | "yellow" | "red",
  "findings": [
    {
      "code": "ONT-01",
      "name": "İsme Tepki",
      "detected": true,
      "latencySec": 2.1,
      "evidenceTimeframe": "00:04 – 00:08",
      "level": "green" | "yellow" | "red",
      "explanation": "Detaylı klinik gözlem açıklaması."
    }
  ]
}`;

    const videoPart = {
      inlineData: {
        data: req.file.buffer.toString('base64'),
        mimeType: req.file.mimetype || 'video/mp4',
      },
    };

    const candidateModels = ['gemini-2.5-flash', 'gemini-2.0-flash', 'gemini-1.5-flash', 'gemini-3.5-flash', 'gemini-3.1-flash-lite'];
    let rawResponse = null;
    let lastError = null;

    for (const mName of candidateModels) {
      try {
        const model = genAI.getGenerativeModel({ model: mName });
        const result = await model.generateContent([prompt, videoPart]);
        rawResponse = result.response.text().trim();
        break;
      } catch (err) {
        console.warn(`[!] Video analizinde ${mName} gecici hata verdi:`, err.message);
        lastError = err;
      }
    }

    if (!rawResponse) {
      throw lastError || new Error('Tum video analiz modelleri gecici olarak mesgul.');
    }

    // JSON temizle ve parse et
    let parsedData;
    try {
      const jsonStr = rawResponse.replace(/```json/g, '').replace(/```/g, '').trim();
      parsedData = JSON.parse(jsonStr);
    } catch (e) {
      console.warn('[!] Analiz yanıtı geçerli JSON değil.');
      return res.status(502).json({
        success: false,
        error: 'Analiz yanıtı geçerli JSON değildi; sonuç üretilmedi.',
      });
    }

    res.json({
      success: true,
      data: parsedData,
    });
  } catch (error) {
    console.error('[!] Video analiz hatası:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Video analiz edilirken hata oluştu.',
    });
  }
});

app.use((error, req, res, next) => {
  if (error.type === 'entity.too.large') {
    return res.status(413).json({ success: false, error: 'İstek gövdesi boyut sınırını aşıyor.' });
  }
  if (error.type === 'entity.parse.failed') {
    return res.status(400).json({ success: false, error: 'İstek geçerli JSON olmalıdır.' });
  }
  next(error);
});
return app;
}

module.exports = { createApp };

// Modül testlerde yalnız uygulamayı oluşturur; dosya okumaz veya port açmaz.
if (require.main === module) {
dotenv.config({ path: path.join(__dirname, '.env') });
dotenv.config();
const app = createApp();
const port = process.env.PORT || 8000;
const deployment = process.env.BACKEND_MODE === 'deployment';
const os = require('os');
function getLocalIps() {
  const nets = os.networkInterfaces();
  const results = [];
  for (const name of Object.keys(nets)) {
    for (const net of nets[name]) {
      if (net.family === 'IPv4' && !net.internal && !net.address.startsWith('169.254')) {
        results.push({ name, ip: net.address });
      }
    }
  }
  return results;
}

app.listen(port, '0.0.0.0', () => {
  const ips = getLocalIps();
  console.log('====================================================');
  console.log(`🚀 Nörogelişimsel Platform Backend Sunucusu Hazır!`);
  console.log(`📡 Bilgisayar İçi (Localhost): http://localhost:${port}`);
  console.log(`📱 Android Emülatör:           http://10.0.2.2:${port}`);
  if (ips.length > 0) {
    ips.forEach((item) => {
      console.log(`📶 Gerçek Telefon (${item.name}): http://${item.ip}:${port}`);
    });
  }
  console.log(`Çalışma modu: ${deployment ? 'deployment' : 'development'}`);
  console.log('====================================================');
});
}
