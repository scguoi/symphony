#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import html
import json
import re
import time
from urllib.parse import parse_qs, urlparse

PROJECT_IDENTIFIER = "FF"
WORKSPACE_SLUG = "demo-workspace"
PROJECT_ID = "demo-project"

states = [
    {"id": "todo", "name": "Todo"},
    {"id": "progress", "name": "In Progress"},
    {"id": "done", "name": "Done"},
]


def now():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def new_work_item(sequence_id, name, description, item_state="todo"):
    timestamp = now()
    return {
        "id": f"demo-work-item-{sequence_id}",
        "name": name,
        "description_stripped": description,
        "priority": "high",
        "sequence_id": sequence_id,
        "state": item_state,
        "project": {"identifier": PROJECT_IDENTIFIER},
        "assignees": [{"id": "demo-worker", "email": "worker@forgeflow.local"}],
        "labels": [{"name": "demo"}],
        "url": f"http://localhost:8000/demo-work-item-{sequence_id}",
        "created_at": timestamp,
        "updated_at": timestamp,
    }


state = {
    "items": [
        new_work_item(
            1,
            "End-to-end ForgeFlow demo",
            "Watch Symphony dispatch this task to an SSH worker.",
        )
    ],
    "comments": {},
    "next_sequence_id": 2,
}


def work_item_id_from_path(path):
    match = re.search(r"/work-items/(demo-work-item-\d+)/", path)
    if match:
        return match.group(1)

    match = re.fullmatch(r"/(demo-work-item-\d+)", path)
    if match:
        return match.group(1)

    return None


def find_work_item(item_id):
    return next((item for item in state["items"] if item["id"] == item_id), None)


def item_identifier(item):
    return f"{PROJECT_IDENTIFIER}-{item['sequence_id']}"


def create_work_item(name, description):
    item = new_work_item(state["next_sequence_id"], name, description)
    state["next_sequence_id"] += 1
    state["items"].append(item)
    return item


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


def redirect(handler, location):
    handler.send_response(303)
    handler.send_header("Location", location)
    handler.end_headers()


def page_shell(title, body):
    return f"""<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{html.escape(title)}</title>
    <style>
      body {{
        color: #172026;
        font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        line-height: 1.5;
        margin: 0;
        padding: 40px;
      }}
      main {{ max-width: 860px; }}
      code {{
        background: #eef2f5;
        border-radius: 4px;
        padding: 2px 6px;
      }}
      a {{ color: #0f6b5f; }}
      form {{
        border: 1px solid #cfd8df;
        border-radius: 8px;
        display: grid;
        gap: 12px;
        margin: 28px 0;
        padding: 18px;
      }}
      label {{ color: #3f4d57; font-weight: 600; }}
      input, textarea {{
        border: 1px solid #b9c5cd;
        border-radius: 6px;
        box-sizing: border-box;
        display: block;
        font: inherit;
        margin-top: 4px;
        padding: 9px 10px;
        width: 100%;
      }}
      button {{
        background: #0f6b5f;
        border: 0;
        border-radius: 6px;
        color: white;
        cursor: pointer;
        font: inherit;
        font-weight: 700;
        justify-self: start;
        padding: 9px 14px;
      }}
      table {{
        border-collapse: collapse;
        margin-top: 16px;
        width: 100%;
      }}
      th, td {{
        border-bottom: 1px solid #e1e7eb;
        padding: 10px 8px;
        text-align: left;
      }}
      th {{ color: #5a6872; font-size: 13px; }}
    </style>
  </head>
  <body>
    <main>{body}</main>
  </body>
</html>"""


def root_page():
    rows = "\n".join(
        f"""<tr>
          <td><a href="/{html.escape(item['id'])}">{html.escape(item_identifier(item))}</a></td>
          <td>{html.escape(item["name"])}</td>
          <td><code>{html.escape(item["state"])}</code></td>
          <td>{html.escape(item["updated_at"])}</td>
        </tr>"""
        for item in sorted(state["items"], key=lambda value: value["sequence_id"])
    )

    body = f"""
      <h1>ForgeFlow Plane Demo</h1>
      <p>Create a work item here, then open the Symphony dashboard to watch it get dispatched to an SSH worker.</p>
      <form method="post" action="/">
        <label>
          Title
          <input name="name" required value="Build a ForgeFlow demo task">
        </label>
        <label>
          Description
          <textarea name="description" rows="4">Create a small result file in the demo repository and mark this task done.</textarea>
        </label>
        <button type="submit">Create task</button>
      </form>
      <p>Dashboard: <a href="http://localhost:4000/">Symphony Observability</a></p>
      <table>
        <thead><tr><th>Issue</th><th>Title</th><th>State</th><th>Updated</th></tr></thead>
        <tbody>{rows}</tbody>
      </table>
    """
    return page_shell("ForgeFlow Plane Demo", body)


def work_item_page(item):
    body = f"""
      <p><a href="/">ForgeFlow Plane Demo</a></p>
      <h1>{html.escape(item_identifier(item))} {html.escape(item["name"])}</h1>
      <p>{html.escape(item["description_stripped"])}</p>
      <p>Status: <code>{html.escape(item["state"])}</code></p>
      <p>Updated: <code>{html.escape(item["updated_at"])}</code></p>
      <p>API: <code>/api/v1/workspaces/{WORKSPACE_SLUG}/projects/{PROJECT_ID}/work-items/{html.escape(item["id"])}/</code></p>
    """
    return page_shell(f"{item_identifier(item)} - ForgeFlow Plane Demo", body)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print(fmt % args, flush=True)

    def do_GET(self):
        parsed = urlparse(self.path)

        if parsed.path == "/":
            html_response(self, 200, root_page())
            return

        item_id = work_item_id_from_path(parsed.path)
        if item_id and not parsed.path.startswith("/api/"):
            item = find_work_item(item_id)
            if item:
                html_response(self, 200, work_item_page(item))
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
            items = [
                item
                for item in state["items"]
                if wanted_state in (None, item["state"])
            ]
            json_response(self, 200, {"results": items})
            return

        item_id = work_item_id_from_path(parsed.path)
        if item_id:
            item = find_work_item(item_id)
            if item:
                json_response(self, 200, item)
                return

        json_response(self, 404, {"error": "not found", "path": parsed.path})

    def do_POST(self):
        parsed = urlparse(self.path)
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length).decode("utf-8") if length else ""

        if parsed.path == "/":
            form = parse_qs(body)
            name = form.get("name", [""])[0].strip()
            description = form.get("description", [""])[0].strip()
            if not name:
                html_response(self, 400, page_shell("Invalid task", "<p>Title is required.</p>"))
                return

            item = create_work_item(name, description or "Created from the ForgeFlow demo page.")
            redirect(self, f"/{item['id']}")
            return

        if parsed.path.endswith("/work-items/"):
            payload = json.loads(body or "{}")
            item = create_work_item(
                str(payload.get("name") or "Untitled ForgeFlow task"),
                str(payload.get("description_stripped") or payload.get("description") or ""),
            )
            json_response(self, 201, item)
            return

        item_id = work_item_id_from_path(parsed.path)
        if item_id and parsed.path.endswith("/comments/"):
            state["comments"].setdefault(item_id, []).append(json.loads(body or "{}"))
            json_response(self, 201, {"ok": True})
            return

        json_response(self, 404, {"error": "not found", "path": parsed.path})

    def do_PATCH(self):
        parsed = urlparse(self.path)
        item_id = work_item_id_from_path(parsed.path)

        if item_id:
            item = find_work_item(item_id)
            if item:
                length = int(self.headers.get("Content-Length", "0"))
                body = json.loads(self.rfile.read(length).decode("utf-8") or "{}")
                if body.get("state") in {"todo", "progress", "done"}:
                    item["state"] = body["state"]
                    item["updated_at"] = now()
                json_response(self, 200, item)
                return

        json_response(self, 404, {"error": "not found", "path": parsed.path})


if __name__ == "__main__":
    server = ThreadingHTTPServer(("0.0.0.0", 8000), Handler)
    print("mock Plane listening on :8000", flush=True)
    server.serve_forever()
