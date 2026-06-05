# syntax=docker/dockerfile:1
FROM node:24-alpine

WORKDIR /app

# install dependencies first so the layer caches when only source changes
COPY package.json ./
RUN npm install --omit=dev

# app source
COPY index.js ./

EXPOSE 4444

# busybox wget ships in the alpine base — used for the container health check
HEALTHCHECK --interval=10s --timeout=2s --start-period=3s \
    CMD wget -qO- http://localhost:4444/ || exit 1

CMD ["node", "index.js"]
