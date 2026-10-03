FROM ruby:4.0.2-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      build-essential git libffi-dev libyaml-dev \
      chromium imagemagick \
      libatk-bridge2.0-0 libatk1.0-0 libcups2 libdbus-1-3 \
      libdrm2 libgbm1 libnspr4 libnss3 libx11-xcb1 \
      libxcomposite1 libxdamage1 libxrandr2 libxshmfence1 \
      fonts-liberation \
      postgresql postgresql-client && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV RAILS_ENV=production

ARG BUILD_ARCH
ARG BUILD_VERSION
LABEL \
    io.hass.name="Timeframe Dev" \
    io.hass.description="An e-paper calendar, weather, and smart home family dashboard" \
    io.hass.version="${BUILD_VERSION}" \
    io.hass.type="app" \
    io.hass.arch="${BUILD_ARCH}"

COPY Gemfile ./
COPY engine/timeframe-core.gemspec engine/
RUN bundle config set --local without 'development test' && \
    bundle install --jobs 4

COPY . .
RUN chmod +x script/docker-start

RUN mkdir -p /data
RUN SECRET_KEY_BASE=precompile \
    TIMEFRAME_HOME_ASSISTANT_TOKEN=precompile \
    RAILS_ENV=production \
    bundle exec rails assets:precompile

ENV PORT=8099

EXPOSE 8099

CMD ["./script/docker-start"]
