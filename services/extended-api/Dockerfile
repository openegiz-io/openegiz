# Extended API for Eclipse Ditto (maintained first-party by OpenEgiz).
#
# Multi-stage build:
#   1. build      - full dev environment, TypeScript compiled to plain JS
#   2. prod-deps  - production-only node_modules, pruned of anything the
#                   runtime does not need to require()
#   3. runtime    - bare Alpine + the Node interpreter. No yarn/npm/ts-node:
#                   the app runs the JavaScript compiled in stage 1.
#
# Every base image used here publishes linux/amd64 and linux/arm64, so the
# result builds multi-arch with no arch-specific steps:
#   docker buildx build --platform linux/amd64,linux/arm64 -t <image> .

# The pinned upstream lockfile (yarn.lock, carried over from
# ertis-research/extended-api-for-eclipse-ditto) pins the dependency tree.
FROM node:22-alpine AS build
WORKDIR /build
COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile
COPY tsconfig.json ./
COPY src ./src
COPY docs ./docs
RUN yarn build

FROM node:22-alpine AS prod-deps
WORKDIR /deps
COPY package.json yarn.lock ./
# --ignore-optional skips the MongoDB driver's native extras (kerberos,
# client-encryption) and S3 credential providers: ditto's policies collection
# is a plain standalone/replica-set URI. Type declarations, source maps and
# docs are deleted: nothing at runtime resolves them.
RUN yarn install --frozen-lockfile --production --ignore-optional \
 && rm -rf node_modules/@types node_modules/.bin node_modules/.yarn* \
 && find node_modules \( -name '*.map' -o -name '*.md' -o -name '*.ts' \) \
      ! \( -iname 'license*' -o -iname 'licence*' -o -iname 'notice*' -o -iname 'copying*' -o -iname 'copyright*' \) -delete \
 && yarn cache clean

FROM alpine:3.24
RUN apk add --no-cache nodejs \
 && addgroup -g 1000 -S node \
 && adduser -S -u 1000 -G node -H -D node
ENV NODE_ENV=production \
    PORT=8080
WORKDIR /usr/src/app
COPY --from=prod-deps /deps/node_modules ./node_modules
COPY --from=build /build/dist ./dist
COPY LICENSE ./LICENSE
USER node
EXPOSE 8080
CMD ["node", "dist/src/app.js"]
