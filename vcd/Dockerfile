FROM elixir:1.19-alpine

RUN apk add --no-cache build-base git bash

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN MIX_ENV=prod mix deps.get --only prod

COPY config/ config/
COPY lib/ lib/

RUN MIX_ENV=prod mix release && \
    mkdir -p /var/vcd

EXPOSE 4000

ENV MIX_ENV=prod

CMD ["/app/_build/prod/rel/vcd/bin/vcd", "start"]
