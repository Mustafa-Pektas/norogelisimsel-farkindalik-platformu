FROM node:24.21.0-bookworm-slim

ENV NODE_ENV=production \
    BACKEND_MODE=deployment \
    PORT=8000

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# Yalnız sunucunun çalıştırdığı modüller, doğrulayıcı ve kanonik kart kaynağı.
COPY --chown=node:node server.js gemini_text.js scenario_input_generation.js \
  scenario_clip_generation.js scenario_comparison.js generation_capacity.js \
  generation_measurement.js ./
COPY --chown=node:node validators/ ./validators/
COPY --chown=node:node resources/Davranis_Kartlari_v02.md ./resources/

USER node
EXPOSE 8000
CMD ["node", "server.js"]
