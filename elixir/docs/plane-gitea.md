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

## Local Docker build

```sh
docker build -t forgeflow-symphony:local .
```

## Local Docker Compose run

```sh
docker compose -f docker-compose.plane-gitea.yml up --build
```

The dashboard listens on `http://localhost:4000` when `server.port` is enabled in the workflow.

## Current limitation

The Docker image contains the Symphony runtime and Git tooling. It expects the configured
`codex.command` to be available in the container or provided by a custom derived image. For a fully
self-contained production image, add the approved Codex runtime installation method to the Dockerfile
used in your deployment.
