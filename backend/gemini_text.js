// Ortak SDK çağrısı; ayrıştırma, tekrar veya başka modele geçiş yapmaz.
async function generateText(genAI, modelName, prompts, { schema, maxOutputTokens }) {
  const model = genAI.getGenerativeModel({
    model: modelName,
    systemInstruction: prompts.system,
    generationConfig: {
      temperature: 0.7,
      maxOutputTokens,
      responseMimeType: 'application/json',
      responseSchema: schema,
    },
  });
  const result = await model.generateContent(prompts.user);
  return result.response.text(); // Boşlukları/ham metni değiştirme.
}
module.exports = { generateText };
