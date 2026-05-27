#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import time
from urllib.parse import parse_qs, urlparse

state = {
    "work_item_state": "todo",
    "comments": [],
    "updated_at": "2026-05-27T00:00:00Z",
}

states = [
    {"id": "todo", "name": "Todo"},
    {"id": "progress", "name": "In Progress"},
    {"id": "done", "name": "Done"},
]


def work_item():
    return {
        "id": "demo-work-item-1",
        "name": "End-to-end ForgeFlow demo",
        "description_stripped": "Watch Symphony dispatch this task to an SSH worker.",
        "priority": "high",
        "sequence_id": 1,
        "state": state["work_item_state"],
        "project": {"identifier": "FF"},
        "assignees": [{"id": "demo-worker", "email": "worker@forgeflow.local"}],
        "labels": [{"name": "demo"}],
        "url": "http://localhost:8000/demo-work-item-1",
        "created_at": "2026-05-27T00:00:00Z",
        "updated_at": state["updated_at"],
    }


def json_response(handler, status, payload):
    body = json.dumps(payload).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


def html_response(handler, status, body):
    encoded = body.encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "text/html; charset=utf-8")
    handler.send_header("Content-Length", str(len(encoded)))
    handler.end_headers()
    handler.wfile.write(encoded)


def root_page():
    item = work_item()
    return f"""<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>ForgeFlow Plane Demo</title>
    <style>
      body {{
        color: #172026;
        font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        line-height: 1.5;
        margin: 0;
        padding: 40px;
      }}
      main {{ max-width: 760px; }}
      code {{
        background: #eef2f5;
        border-radius: 4px;
        padding: 2px 6px;
      }}
      a {{ color: #0f6b5f; }}
      dl {{ display: grid; grid-template-columns: 140px 1fr; gap: 8px 16px; }}
      dt {{ color: #5a6872; }}
      dd {{ margin: 0; }}
    </style>
  </head>
  <body>
    <main>
      <h1>ForgeFlow Plane Demo</h1>
      <p>This is the local mock Plane service used by the ForgeFlow end-to-end SSH worker demo.</p>
      <dl>
        <dt>Work item</dt>
        <dd><a href="/demo-work-item-1">FF-1 {item["name"]}</a></dd>
        <dt>Current state</dt>
        <dd><code>{item["state"]}</code></dd>
        <dt>Dashboard</dt>
        <dd><a href="http://localhost:4000/">Symphony Observability</a></dd>
        <dt>API</dt>
        <dd><code>/api/v1/workspaces/demo-workspace/projects/demo-project/work-items/demo-work-item-1/</code></dd>
      </dl>
    </main>
  </body>
</html>"""


def work_item_page():
    item = work_item()
    return f"""<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>FF-1 - ForgeFlow Plane Demo</title>
    <style>
      body {{
        color: #172026;
        font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        line-height: 1.5;
        margin: 0;
        padding: 40px;
      }}
      main {{ max-width: 760px; }}
      code {{
        background: #eef2f5;
        border-radius: 4px;
        padding: 2px 6px;
      }}
      a {{ color: #0f6b5f; }}
    </style>
  </head>
  <body>
    <main>
      <p><a href="/">ForgeFlow Plane Demo</a></p>
      <h1>FF-1 {item["name"]}</h1>
      <p>{item["description_stripped"]}</p>
      <p>Status: <code>{item["state"]}</code></p>
      <p>Updated: <code>{item["updated_at"]}</code></p>
      <p>API: <code>/api/v1/workspaces/demo-workspace/projects/demo-project/work-items/demo-work-item-1/</code></p>
    </main>
  </body>
</html>"""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print(fmt % args, flush=True)

    def do_GET(self):
        parsed = urlparse(self.path)

        if parsed.path == "/":
            html_response(self, 200, root_page())
            return

        if parsed.path == "/demo-work-item-1":
            html_response(self, 200, work_item_page())
            return

        if parsed.path == "/favicon.ico":
            self.send_response(204)
            self.end_headers()
            return

        if parsed.path.endswith("/states/"):
            json_response(self, 200, {"results": states})
            return

        if parsed.path.endswith("/work-items/"):
            query = parse_qs(parsed.query)
            wanted_state = query.get("state", [None])[0]
            item = work_item()
            results = [item] if wanted_state in (None, item["state"]) else []
            json_response(self, 200, {"results": results})
            return

        if parsed.path.endswith("/work-items/demo-work-item-1/"):
            json_response(self, 200, work_item())
            return

        json_response(self, 404, {"error": "not found", "path": parsed.path})

    def do_POST(self):
        parsed = urlparse(self.path)
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length).decode("utf-8") if length else "{}"

        if parsed.path.endswith("/work-items/demo-work-item-1/comments/"):
            state["comments"].append(json.loads(body or "{}"))
            json_response(self, 201, {"ok": True})
            return

        json_response(self, 404, {"error": "not found", "path": parsed.path})

    def do_PATCH(self):
        parsed = urlparse(self.path)

        if parsed.path.endswith("/work-items/demo-work-item-1/"):
            length = int(self.headers.get("Content-Length", "0"))
            body = json.loads(self.rfile.read(length).decode("utf-8") or "{}")
            if body.get("state") in {"todo", "progress", "done"}:
                state["work_item_state"] = body["state"]
                state["updated_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            json_response(self, 200, work_item())
            return

        json_response(self, 404, {"error": "not found", "path": parsed.path})


if __name__ == "__main__":
    server = ThreadingHTTPServer(("0.0.0.0", 8000), Handler)
    print("mock Plane listening on :8000", flush=True)
    server.serve_forever()
