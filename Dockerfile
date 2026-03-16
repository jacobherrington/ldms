FROM ruby:3.3-slim

WORKDIR /app

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential curl \
  && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock ./
RUN bundle config set without 'development' \
  && bundle install

COPY . .

ENV LDMS_PROJECT_ID=dev-memory

CMD ["bash", "scripts/run.sh"]
