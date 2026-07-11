# 构建 Next.js 前端产物。
FROM oven/bun:1.3.13 AS web-build

ARG NEXT_BASE_PATH=
ENV NEXT_BASE_PATH=$NEXT_BASE_PATH

WORKDIR /app/web
COPY web/package.json web/bun.lock ./
RUN --mount=type=cache,target=/root/.bun/install/cache bun install --frozen-lockfile --cache-dir=/root/.bun/install/cache
COPY VERSION /app/VERSION
COPY CHANGELOG.md /app/CHANGELOG.md
COPY web ./
ARG NEXT_PUBLIC_DOC_URL=https://gptch.cloud/image/manual/index.html
ENV NEXT_PUBLIC_DOC_URL=$NEXT_PUBLIC_DOC_URL
RUN bun run build

# 运行镜像：只启动 Next.js，AI 请求由浏览器前台直连用户自己的接口。
FROM node:22-bookworm-slim

WORKDIR /app
COPY VERSION /app/VERSION
COPY CHANGELOG.md /app/CHANGELOG.md
COPY --from=web-build /app/web/public /app/web/public
COPY --from=web-build /app/web/.next/standalone /app/web
COPY --from=web-build /app/web/.next/static /app/web/.next/static
ENV NODE_ENV=production
ENV HOSTNAME=0.0.0.0
ENV PORT=3000
ENV NEXT_BASE_PATH=
RUN apt-get -o Acquire::Retries=5 update && apt-get -o Acquire::Retries=5 install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*

EXPOSE 3000
CMD ["sh", "-c", "cd /app/web && PORT=3000 node server.js"]
