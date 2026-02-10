# --- Build stage ---
FROM oven/bun:1 AS build

WORKDIR /app

COPY package.json bun.lock ./
RUN bun install --frozen-lockfile

COPY . .
RUN bun run build

# --- Runtime stage ---
FROM node:22-alpine

WORKDIR /app

COPY --from=build /app/build ./build
COPY --from=build /app/package.json .

ENV NODE_ENV=production
ENV PORT=3000
ENV HOST=0.0.0.0

# Public env vars are read at runtime by adapter-node
# Pass at `docker run` with -e, e.g.:
#   docker run -e PUBLIC_SPOTIFY_CLIENT_ID=xxx ...
ENV PUBLIC_SPOTIFY_CLIENT_ID=""

EXPOSE 3000

CMD ["node", "build"]
