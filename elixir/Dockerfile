FROM elixir:1.19.5-otp-28-slim AS build

RUN apt-get update && apt-get install -y --no-install-recommends build-essential git ca-certificates && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

COPY config config
COPY lib lib
COPY priv priv

RUN mix escript.build

FROM elixir:1.19.5-otp-28-slim

RUN apt-get update && apt-get install -y --no-install-recommends bash ca-certificates git openssh-client && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV SYMPHONY_WORKSPACE_ROOT=/workspaces

COPY --from=build /app/bin/symphony /usr/local/bin/symphony
COPY WORKFLOW.plane-gitea.md /app/WORKFLOW.md

RUN mkdir -p /workspaces

EXPOSE 4000

ENTRYPOINT ["symphony"]
CMD ["/app/WORKFLOW.md"]
