---
tracker:
  kind: plane
  endpoint: "http://forgeflow-plane-demo:8000"
  api_key: "demo-key"
  workspace_slug: "demo-workspace"
  project_id: "demo-project"
  project_identifier: "FF"
  active_states: ["Todo"]
  terminal_states: ["Done"]
polling:
  interval_ms: 5000
workspace:
  root: "/workspaces"
worker:
  ssh_hosts:
    - "forgeflow-worker-1:22"
    - "forgeflow-worker-2:22"
  max_concurrent_agents_per_host: 2
agent:
  max_concurrent_agents: 4
  max_turns: 1
codex:
  command: "env DEMO_TURN_DELAY_SECONDS=25 DEMO_PLANE_BASE_URL=http://forgeflow-plane-demo:8000 forgeflow-demo-app-server"
  thread_sandbox: "workspace-write"
  turn_timeout_ms: 120000
hooks:
  timeout_ms: 300000
  after_create: "git clone file:///demo/gitea-repo.git ."
observability:
  dashboard_enabled: true
server:
  host: "0.0.0.0"
  port: 4000
---
You are working on a local ForgeFlow demo work item.

This workflow is intentionally self-contained: mock Plane creates the task, Symphony dispatches it to
an SSH worker, the worker clones a local demo repository, and the demo app-server writes a result
file before marking the mock Plane task as Done.
