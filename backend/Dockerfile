# =============================================================================
# Backend — build multi-etapa.
# La imagen final solo lleva dependencias de producción y el dist compilado.
# =============================================================================

FROM node:22-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci

FROM node:22-alpine AS build
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build

FROM node:22-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production
# Zona horaria de Lima: las fechas clínicas y los cortes de caja dependen de ella.
ENV TZ=America/Lima
RUN apk add --no-cache tzdata

COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY --from=build /app/dist ./dist

# Usuario sin privilegios
RUN addgroup -S app && adduser -S app -G app
USER app

EXPOSE 3100
# /api/health responde 503 si falta la base, Redis o MinIO.
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:3100/api/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", "dist/main.js"]
