defmodule SymphonyElixir.PlaneClientTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Plane.Client, as: PlaneClient

  test "plane tracker validates required settings and resolves env vars" do
    previous_api_key = System.get_env("PLANE_API_KEY")
    previous_endpoint = System.get_env("PLANE_API_BASE_URL")
    previous_workspace = System.get_env("PLANE_WORKSPACE_SLUG")
    previous_project = System.get_env("PLANE_PROJECT_ID")
    previous_identifier = System.get_env("PLANE_PROJECT_IDENTIFIER")

    on_exit(fn ->
      restore_env("PLANE_API_KEY", previous_api_key)
      restore_env("PLANE_API_BASE_URL", previous_endpoint)
      restore_env("PLANE_WORKSPACE_SLUG", previous_workspace)
      restore_env("PLANE_PROJECT_ID", previous_project)
      restore_env("PLANE_PROJECT_IDENTIFIER", previous_identifier)
    end)

    System.put_env("PLANE_API_KEY", "plane-key")
    System.put_env("PLANE_API_BASE_URL", "https://plane.example")
    System.put_env("PLANE_WORKSPACE_SLUG", "forgeflow")
    System.put_env("PLANE_PROJECT_ID", "project-uuid")
    System.put_env("PLANE_PROJECT_IDENTIFIER", "FF")

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "plane",
      tracker_endpoint: "$PLANE_API_BASE_URL",
      tracker_api_token: nil,
      tracker_project_slug: nil,
      tracker_workspace_slug: nil,
      tracker_project_id: nil,
      tracker_project_identifier: "$PLANE_PROJECT_IDENTIFIER"
    )

    settings = Config.settings!()

    assert settings.tracker.endpoint == "https://plane.example"
    assert settings.tracker.api_key == "plane-key"
    assert settings.tracker.workspace_slug == "forgeflow"
    assert settings.tracker.project_id == "project-uuid"
    assert settings.tracker.project_identifier == "FF"
    assert :ok = Config.validate!()

    System.delete_env("PLANE_PROJECT_IDENTIFIER")

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "plane",
      tracker_workspace_slug: "forgeflow",
      tracker_project_id: "project-uuid",
      tracker_project_identifier: "$PLANE_PROJECT_IDENTIFIER"
    )

    assert Config.settings!().tracker.project_identifier == nil

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "plane",
      tracker_api_token: nil,
      tracker_workspace_slug: "forgeflow",
      tracker_project_id: "project-uuid"
    )

    System.delete_env("PLANE_API_KEY")
    assert {:error, :missing_plane_api_token} = Config.validate!()
  end

  test "normalizes expanded Plane work items into tracker issues" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "plane",
      tracker_workspace_slug: "forgeflow",
      tracker_project_id: "project-uuid",
      tracker_project_identifier: "FF",
      tracker_assignee: "agent@example.com"
    )

    states = [%{"id" => "state-started", "name" => "In Progress"}]

    work_item = %{
      "id" => "work-item-1",
      "name" => "Wire Plane adapter",
      "description_html" => "<p>Build it</p>",
      "priority" => "high",
      "sequence_id" => 42,
      "state" => %{"id" => "state-started", "name" => "In Progress"},
      "project" => %{"identifier" => "FF"},
      "assignees" => [%{"id" => "user-1", "email" => "agent@example.com"}],
      "labels" => [%{"name" => "Backend"}],
      "created_at" => "2026-05-26T10:00:00Z",
      "updated_at" => "2026-05-26T11:00:00Z"
    }

    issue = PlaneClient.normalize_work_item_for_test(work_item, states)

    assert issue.id == "work-item-1"
    assert issue.identifier == "FF-42"
    assert issue.title == "Wire Plane adapter"
    assert issue.description == "Build it"
    assert issue.priority == 2
    assert issue.state == "In Progress"
    assert issue.labels == ["backend"]
    assert issue.assignee_id == "user-1"
    assert issue.assigned_to_worker
  end

  test "resolves Plane state names to state ids" do
    states = [
      %{"id" => "todo-id", "name" => "Todo"},
      %{"id" => "progress-id", "name" => "In Progress"}
    ]

    assert {:ok, ["todo-id", "progress-id"]} =
             PlaneClient.resolve_state_ids_for_test(states, ["todo", "IN PROGRESS"])

    assert {:error, {:plane_state_not_found, "Review"}} =
             PlaneClient.resolve_state_ids_for_test(states, ["Review"])
  end
end
