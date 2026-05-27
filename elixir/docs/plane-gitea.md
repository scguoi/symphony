# Plane + Gitea Runtime

This is the first ForgeFlow-oriented Symphony runtime path. It keeps Symphony as the orchestration
engine, uses Plane as the tracker, and bootstraps each agent workspace from a Gitea repository.

## What is implemented

- `tracker.kind: plane`
- Plane work item polling through the `/work-items/` API
- Plane state lookup by state name
- Plane comments through work item comments
- Plane state updates by target state name
- A Docker image for the Symphony runtime
- A Docker Compose file for local deployment
- A `WORKFLOW.plane-gitea.md` template that clones a Gitea repository into each workspace

## Required Plane settings

Set these values before running the container:

- `PLANE_API_BASE_URL`: Plane API base URL. Use `https://api.plane.so` for Plane Cloud or your
  self-hosted Plane base URL.
- `PLANE_API_KEY`: Plane API key.
- `PLANE_WORKSPACE_SLUG`: Plane workspace slug.
- `PLANE_PROJECT_ID`: Plane project UUID.
- `PLANE_PROJECT_IDENTIFIER`: Optional project key used to render identifiers such as `FF-42`.
- `PLANE_ASSIGNEE`: Optional assignee filter. It can match an expanded Plane assignee id, email, or
  display name.

Plane's API now recommends `/work-items/` instead of the older `/issues/` endpoints, so the adapter
uses work item endpoints.

## Required Gitea settings

Set:

- `GITEA_REPOSITORY_URL`: Git clone URL for the repository agents should modify.
- `GITEA_UPSTREAM_URL`: Optional upstream remote URL.

The first implementation uses Symphony hooks and agent workflow instructions for Gitea. It does not
yet call Gitea's pull request API directly.

## Worker model

The Symphony container is the orchestrator. It should not bake in Codex, Claude Code, or any other
programming agent runtime. Agent execution belongs on worker machines or worker containers.
See `docs/distributed-workers.md` for the target ForgeFlow worker architecture.

Configure workers through the workflow file:

```yaml
worker:
  ssh_hosts: ["worker-01:22", "worker-02:22"]
  max_concurrent_agents_per_host: 3
codex:
  command: "codex app-server"
```

Symphony connects to each worker over SSH, creates the task workspace there, runs workspace hooks,
and starts the configured agent command from inside that workspace. Each worker is responsible for
having the requested agent runtime and credentials installed.

For SSH worker access, the Compose file mounts:

- `${HOME}/.ssh` -> `/root/.ssh`

## Local Docker build

```sh
docker build -t forgeflow-symphony:local .
```

## Local Docker Compose run

```sh
docker compose -f docker-compose.plane-gitea.yml up --build
```

The dashboard listens on `http://localhost:4000` when `server.port` is enabled in the workflow.

For a local distributed MVP with two Codex SSH workers, use:

```sh
docker compose -f docker-compose.plane-gitea.local-workers.yml up --build
```

## Local smoke tests

```sh
docker run --rm forgeflow-symphony:orchestrator --help
```

## Current limitation

This runtime path wires Symphony to Plane and Gitea, but it does not package a worker image yet.
Workers must be provisioned separately with SSH, Git, the selected agent runtime, credentials, and
the project build toolchain.
