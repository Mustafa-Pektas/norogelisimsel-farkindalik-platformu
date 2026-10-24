// Ortak SDK çağrısı; ayrıştırma, tekrar veya başka modele geçiş yapmaz.
async function generateTextWithUsage(genAI, modelName, prompts, { schema, maxOutputTokens, temperature = 0.7, topP }) {
  const model = genAI.getGenerativeModel({
    model: modelName,
    systemInstruction: prompts.system,
    generationConfig: {
      temperature,
      ...(topP === undefined ? {} : { topP }),
      maxOutputTokens,
      responseMimeType: 'application/json',
      responseSchema: schema,
    },
  });
  const result = await model.generateContent(prompts.user);
  const text = result.response.text(); // Boşlukları/ham metni değiştirme.
  let promptTokens = null, outputTokens = null;
  try {
    const usage = result.response.usageMetadata;
    if (Number.isSafeInteger(usage?.promptTokenCount) && usage.promptTokenCount >= 0) promptTokens = usage.promptTokenCount;
    if (Number.isSafeInteger(usage?.candidatesTokenCount) && usage.candidatesTokenCount >= 0) outputTokens = usage.candidatesTokenCount;
  } catch (_) { /* Ölçüm okunamazsa metin yanıtı korunur. */ }
  return { text, usage: { promptTokens, outputTokens } };
}
// Eski 26 sahne yolu ve mevcut tüketicilerin metin sözleşmesi korunur.
async function generateText(...args) { return (await generateTextWithUsage(...args)).text; }
module.exports = { generateText, generateTextWithUsage };
