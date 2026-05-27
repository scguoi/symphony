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
  command: "codex app-server"
  approval_policy: "never"
  thread_sandbox: "danger-full-access"
  turn_sandbox_policy:
    type: "dangerFullAccess"
  turn_timeout_ms: 600000
hooks:
  timeout_ms: 300000
  after_create: "git clone file:///demo/gitea-repo.git . && mkdir -p src/generated forgeflow-results"
  after_run: "DEMO_PLANE_BASE_URL=http://forgeflow-plane-demo:8000 forgeflow-demo-after-run"
observability:
  dashboard_enabled: true
server:
  host: "0.0.0.0"
  port: 4000
---
You are working on a local ForgeFlow demo work item: {{ issue.identifier }}.

This workflow is intentionally self-contained: mock Plane creates the task, Symphony dispatches it to
an SSH worker, the worker clones a local demo repository, and Codex makes the requested code change.

Task title: {{ issue.title }}

Task description:
{{ issue.description }}

Make a concrete repository change that demonstrates the task was handled. Keep the change small and
deterministic. For this demo, create or update files under `src/generated/` using the issue
identifier in the file name, and include a short Markdown note under `forgeflow-results/`.

Do not commit changes. The worker after-run hook will commit, push, and publish the patch back to the
mock Plane task page.
