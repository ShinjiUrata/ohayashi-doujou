# =============================================================================
# Multi-stage build: compile TypeScript in builder, run slim in runtime
# =============================================================================

FROM node:20-alpine AS builder
WORKDIR /app

# 依存インストール (dev deps 含む、TypeScript コンパイルに必要)
COPY package.json ./
RUN npm install --no-audit --no-fund

COPY tsconfig.json ./
COPY src ./src

RUN npm run build

# 本番依存のみ
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev --no-audit --no-fund

# =============================================================================
# Runtime
# =============================================================================

FROM node:20-alpine AS runtime
WORKDIR /app

ENV NODE_ENV=production
# Cloud Run が指定する PORT を読む
ENV PORT=8080

COPY --from=deps /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY package.json ./

# ノンルートユーザーで実行
RUN adduser -D -u 10001 app
USER app

EXPOSE 8080
CMD ["node", "dist/index.js"]
