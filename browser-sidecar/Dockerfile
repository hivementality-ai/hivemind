FROM mcr.microsoft.com/playwright:v1.52.0-noble

RUN addgroup --system sidecar && adduser --system sidecar --ingroup sidecar

WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm install --production

COPY . .
RUN chown -R sidecar:sidecar /app

USER sidecar

EXPOSE 3004

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -qO- http://localhost:3004/health || exit 1

CMD ["node", "server.js"]
