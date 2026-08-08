FROM node:22-alpine

RUN addgroup -S proxy && adduser -S proxy -G proxy

WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm install --production && npm install -g @anthropic-ai/claude-code

COPY . .
RUN chown -R proxy:proxy /app

USER proxy

EXPOSE 3003

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1:3003/health || exit 1

CMD ["node", "server.js"]
