# syntax=docker/dockerfile:1.10

# -----------------------------
# BUILDER LAYER
# -----------------------------
ARG CODE_ROOT=/app
ARG ONETIME_HOME=/opt/onetime
ARG VERSION

FROM docker.io/library/ruby:3.4-slim-bookworm AS base

ARG PACKAGES="build-essential rsync netcat-openbsd libffi-dev libyaml-dev git"

RUN set -eux \
  && apt-get update \
  && apt-get install -y $PACKAGES \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

COPY --from=docker.io/library/node:22 /usr/local/bin/node /usr/local/bin/
COPY --from=docker.io/library/node:22 /usr/local/lib/node_modules /usr/local/lib/node_modules

RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
  && ln -s /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

RUN gem install bundler && npm install -g pnpm

# -----------------------------
# DEPENDENCIES LAYER
# -----------------------------
FROM base AS app_deps

ARG CODE_ROOT
ARG ONETIME_HOME
WORKDIR $CODE_ROOT
ENV NODE_PATH=$CODE_ROOT/node_modules

COPY Gemfile Gemfile.lock ./
COPY package.json pnpm-lock.yaml ./

RUN bundle config set --local without 'development test' \
  && bundle install \
  && pnpm install --frozen-lockfile

# -----------------------------
# BUILD LAYER
# -----------------------------
FROM app_deps AS build

ARG CODE_ROOT
WORKDIR $CODE_ROOT

COPY public ./public
COPY templates ./templates
COPY src ./src
COPY package.json pnpm-lock.yaml tsconfig.json vite.config.ts postcss.config.mjs tailwind.config.ts eslint.config.ts ./

RUN pnpm run build \
  && pnpm prune --prod

RUN VERSION=$(node -p "require('./package.json').version") \
  && mkdir -p /tmp/build-meta \
  && echo "VERSION=$VERSION" > /tmp/build-meta/version_env \
  && if [ ! -f /tmp/build-meta/commit_hash.txt ]; then \
      date -u +%s > /tmp/build-meta/commit_hash.txt; \
    fi

# -----------------------------
# FINAL APPLICATION LAYER
# -----------------------------
FROM ruby:3.4-slim-bookworm AS final

ARG CODE_ROOT
WORKDIR $CODE_ROOT

COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build $CODE_ROOT/public $CODE_ROOT/public
COPY --from=build $CODE_ROOT/templates $CODE_ROOT/templates
COPY --from=build $CODE_ROOT/src $CODE_ROOT/src

COPY bin ./bin
COPY apps ./apps
COPY etc ./etc
COPY lib ./lib
COPY migrate ./migrate
COPY package.json config.ru Gemfile Gemfile.lock ./

COPY --from=build /tmp/build-meta/commit_hash.txt .commit_hash.txt

ENV RACK_ENV=production
ENV RUBY_YJIT_ENABLE=1

# ✅ Inject a secure site secret into config.yaml at build time
RUN set -eux \
  && cp --preserve --no-clobber etc/config.example.yaml etc/config.yaml \
  && sed -i "s/:secret:.*/:secret: $(openssl rand -hex 32)/" etc/config.yaml

EXPOSE 3000
CMD ["bin/entrypoint.sh"]
