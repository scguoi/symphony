---
tracker:
  kind: plane
  endpoint: "$PLANE_API_BASE_URL"
  api_key: "$PLANE_API_KEY"
  workspace_slug: "$PLANE_WORKSPACE_SLUG"
  project_id: "$PLANE_PROJECT_ID"
  project_identifier: "$PLANE_PROJECT_IDENTIFIER"
  assignee: "$PLANE_ASSIGNEE"
  active_states: ["Todo", "In Progress"]
  terminal_states: ["Done", "Cancelled", "Canceled"]
polling:
  interval_ms: 30000
workspace:
  root: "/workspaces"
worker:
  ssh_hosts:
    - "forgeflow-worker-1:22"
    - "forgeflow-worker-2:22"
  max_concurrent_agents_per_host: 2
agent:
  max_concurrent_agents: 4
  max_turns: 20
codex:
  command: "codex app-server"
  thread_sandbox: "workspace-write"
hooks:
  timeout_ms: 300000
  after_create: "git clone ${GITEA_REPOSITORY_URL} . && git remote add upstream ${GITEA_UPSTREAM_URL:-${GITEA_REPOSITORY_URL}} || true"
observability:
  dashboard_enabled: true
server:
  host: "0.0.0.0"
  port: 4000
---
You are working on a Plane work item `{{ issue.identifier }}`.

Title: {{ issue.title }}
State: {{ issue.state }}
URL: {{ issue.url }}

Description:
{% if issue.description %}
{{ issue.description }}
{% else %}
No description provided.
{% endif %}

Use the checked-out Gitea repository in the current worker workspace. Create a focused branch, make
the smallest correct change, run relevant verification, and publish the result back to the configured
Gitea remote when credentials are available. Keep the Plane work item updated with concise progress,
proof of work, and blockers.
