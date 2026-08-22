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
CMD ["node", "dist/main.js"]
