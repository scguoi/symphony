defmodule SymphonyElixir.Plane.Client do
  @moduledoc """
  Plane REST client for polling work items.
  """

  require Logger

  alias SymphonyElixir.{Config, Linear.Issue}

  @cloud_endpoint "https://api.plane.so"
  @page_size 50
  @max_error_body_log_bytes 1_000

  @spec fetch_candidate_issues() :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_candidate_issues do
    with :ok <- validate_config(),
         {:ok, states} <- fetch_states(),
         {:ok, assignee_filter} <- routing_assignee_filter(),
         {:ok, state_ids} <- resolve_state_ids(states, Config.settings!().tracker.active_states) do
      fetch_work_items_by_state_ids(state_ids, states, assignee_filter)
    end
  end

  @spec fetch_issues_by_states([String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issues_by_states(state_names) when is_list(state_names) do
    normalized_states = Enum.map(state_names, &to_string/1) |> Enum.uniq()

    if normalized_states == [] do
      {:ok, []}
    else
      with :ok <- validate_config(),
           {:ok, states} <- fetch_states(),
           {:ok, state_ids} <- resolve_state_ids(states, normalized_states) do
        fetch_work_items_by_state_ids(state_ids, states, nil)
      end
    end
  end

  @spec fetch_issue_states_by_ids([String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids) when is_list(issue_ids) do
    ids = Enum.uniq(issue_ids)

    if ids == [] do
      {:ok, []}
    else
      with :ok <- validate_config(),
           {:ok, states} <- fetch_states(),
           {:ok, assignee_filter} <- routing_assignee_filter() do
        fetch_work_items_by_ids(ids, states, assignee_filter)
      end
    end
  end

  @spec list_states(keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_states(opts \\ []) do
    with :ok <- validate_config(),
         {:ok, %{status: status, body: body}} when status in 200..299 <-
           request(:get, project_path("/states/"), %{}, opts) do
      {:ok, list_payload(body)}
    else
      {:ok, response} ->
        plane_status_error("Plane state list failed", response)

      {:error, reason}
      when reason in [:missing_plane_api_token, :missing_plane_workspace_slug, :missing_plane_project_id] ->
        {:error, reason}

      {:error, reason} ->
        plane_request_error(reason)
    end
  end

  @spec create_comment(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def create_comment(work_item_id, body, opts \\ [])
      when is_binary(work_item_id) and is_binary(body) do
    payload = %{
      "comment_html" => "<p>" <> html_escape(body) <> "</p>",
      "access" => "EXTERNAL",
      "external_source" => "symphony"
    }

    with :ok <- validate_config() do
      case request(:post, work_item_path(work_item_id, "/comments/"), payload, opts) do
        {:ok, %{status: status}} when status in 200..299 -> :ok
        {:ok, response} -> plane_status_error("Plane comment create failed", response)
        {:error, reason} -> plane_request_error(reason)
      end
    end
  end

  @spec update_work_item_state(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def update_work_item_state(work_item_id, state_name, opts \\ [])
      when is_binary(work_item_id) and is_binary(state_name) do
    with {:ok, states} <- list_states(opts),
         {:ok, state_id} <- resolve_one_state_id(states, state_name) do
      case request(:patch, work_item_path(work_item_id, "/"), %{"state" => state_id}, opts) do
        {:ok, %{status: status}} when status in 200..299 -> :ok
        {:ok, response} -> plane_status_error("Plane work item update failed", response)
        {:error, reason} -> plane_request_error(reason)
      end
    end
  end

  @doc false
  @spec normalize_work_item_for_test(map(), [map()]) :: Issue.t() | nil
  def normalize_work_item_for_test(work_item, states \\ []) when is_map(work_item) do
    normalize_work_item(work_item, state_index(states), nil)
  end

  @doc false
  @spec resolve_state_ids_for_test([map()], [String.t()]) :: {:ok, [String.t()]} | {:error, term()}
  def resolve_state_ids_for_test(states, state_names), do: resolve_state_ids(states, state_names)

  defp validate_config do
    tracker = Config.settings!().tracker

    cond do
      not is_binary(tracker.api_key) -> {:error, :missing_plane_api_token}
      not is_binary(tracker.workspace_slug) -> {:error, :missing_plane_workspace_slug}
      not is_binary(tracker.project_id) -> {:error, :missing_plane_project_id}
      true -> :ok
    end
  end

  defp fetch_states, do: list_states()

  defp fetch_work_items_by_state_ids(state_ids, states, assignee_filter) do
    state_index = state_index(states)

    state_ids
    |> Enum.reduce_while({:ok, []}, fn state_id, {:ok, acc} ->
      case fetch_work_item_pages(%{"state" => state_id}, state_index, assignee_filter) do
        {:ok, issues} -> {:cont, {:ok, issues ++ acc}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, issues} -> {:ok, issues |> Enum.reverse() |> uniq_issues()}
      error -> error
    end
  end

  defp fetch_work_items_by_ids(ids, states, assignee_filter) do
    state_index = state_index(states)

    ids
    |> Enum.reduce_while({:ok, []}, fn id, {:ok, acc} ->
      case request(:get, work_item_path(id, "/"), %{}, query: [expand: "assignees,state,labels,project"]) do
        {:ok, %{status: status, body: body}} when status in 200..299 ->
          {:cont, {:ok, [normalize_work_item(body, state_index, assignee_filter) | acc]}}

        {:ok, %{status: 404}} ->
          {:cont, {:ok, acc}}

        {:ok, response} ->
          {:halt, plane_status_error("Plane work item fetch failed", response)}

        {:error, reason} ->
          {:halt, plane_request_error(reason)}
      end
    end)
    |> case do
      {:ok, issues} -> {:ok, issues |> Enum.reject(&is_nil/1) |> Enum.reverse()}
      error -> error
    end
  end

  defp fetch_work_item_pages(params, state_index, assignee_filter, offset \\ 0, acc \\ []) do
    query =
      params
      |> Map.merge(%{"limit" => @page_size, "offset" => offset, "expand" => "assignees,state,labels,project"})
      |> Enum.to_list()

    case request(:get, project_path("/work-items/"), %{}, query: query) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        items = list_payload(body)

        issues =
          items
          |> Enum.map(&normalize_work_item(&1, state_index, assignee_filter))
          |> Enum.reject(&is_nil/1)

        if length(items) >= @page_size do
          fetch_work_item_pages(params, state_index, assignee_filter, offset + @page_size, issues ++ acc)
        else
          {:ok, Enum.reverse(issues ++ acc)}
        end

      {:ok, response} ->
        plane_status_error("Plane work item list failed", response)

      {:error, reason} ->
        plane_request_error(reason)
    end
  end

  defp request(method, path, payload, opts) do
    request_fun = Keyword.get(opts, :request_fun, &Req.request/1)
    query = Keyword.get(opts, :query, [])

    request_opts = [
      method: method,
      url: endpoint() <> path,
      headers: headers(),
      params: query,
      connect_options: [timeout: 30_000]
    ]

    request_fun.(maybe_put_json(request_opts, method, payload))
  end

  defp maybe_put_json(request_opts, method, payload) when method in [:post, :patch] do
    Keyword.put(request_opts, :json, payload)
  end

  defp maybe_put_json(request_opts, _method, _payload), do: request_opts

  defp endpoint do
    tracker = Config.settings!().tracker

    case tracker.endpoint do
      endpoint when is_binary(endpoint) and endpoint != "https://api.linear.app/graphql" ->
        String.trim_trailing(endpoint, "/")

      _ ->
        @cloud_endpoint
    end
  end

  defp headers do
    [
      {"x-api-key", Config.settings!().tracker.api_key},
      {"Content-Type", "application/json"}
    ]
  end

  defp project_path(suffix) do
    tracker = Config.settings!().tracker

    "/api/v1/workspaces/#{URI.encode(tracker.workspace_slug)}/projects/#{URI.encode(tracker.project_id)}" <>
      suffix
  end

  defp work_item_path(work_item_id, suffix) do
    project_path("/work-items/#{URI.encode(work_item_id)}" <> suffix)
  end

  defp resolve_state_ids(states, state_names) do
    states_by_name = Map.new(states, fn state -> {normalize_name(state["name"]), state["id"]} end)

    state_names
    |> Enum.map(&resolve_state_id(states_by_name, &1))
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, id}, {:ok, ids} -> {:cont, {:ok, [id | ids]}}
      {:error, reason}, _acc -> {:halt, {:error, reason}}
    end)
    |> case do
      {:ok, ids} -> {:ok, ids |> Enum.reverse() |> Enum.uniq()}
      error -> error
    end
  end

  defp resolve_one_state_id(states, state_name) do
    with {:ok, [state_id]} <- resolve_state_ids(states, [state_name]) do
      {:ok, state_id}
    end
  end

  defp resolve_state_id(states_by_name, state_name) do
    normalized = normalize_name(state_name)

    case Map.get(states_by_name, normalized) do
      id when is_binary(id) -> {:ok, id}
      _ -> {:error, {:plane_state_not_found, state_name}}
    end
  end

  defp state_index(states) when is_list(states) do
    Map.new(states, fn state -> {state["id"], state} end)
  end

  defp normalize_work_item(work_item, state_index, assignee_filter) when is_map(work_item) do
    project = map_value(work_item, "project")
    state = resolve_state(map_value(work_item, "state"), state_index)
    labels = map_list(work_item, "labels")
    assignees = map_list(work_item, "assignees")

    %Issue{
      id: work_item["id"],
      identifier: work_item_identifier(work_item, project),
      title: work_item["name"],
      description: work_item["description_stripped"] || strip_html(work_item["description_html"]),
      priority: parse_priority(work_item["priority"]),
      state: state && state["name"],
      branch_name: nil,
      url: work_item_url(work_item),
      assignee_id: assignee_ids(assignees) |> List.first(),
      blocked_by: [],
      labels: label_names(labels),
      assigned_to_worker: assigned_to_worker?(assignees, assignee_filter),
      created_at: parse_datetime(work_item["created_at"]),
      updated_at: parse_datetime(work_item["updated_at"])
    }
  end

  defp normalize_work_item(_work_item, _state_index, _assignee_filter), do: nil

  defp work_item_identifier(work_item, project) do
    cond do
      is_binary(work_item["identifier"]) ->
        work_item["identifier"]

      is_map(project) and is_binary(project["identifier"]) and is_integer(work_item["sequence_id"]) ->
        "#{project["identifier"]}-#{work_item["sequence_id"]}"

      is_binary(Config.settings!().tracker.project_identifier) and is_integer(work_item["sequence_id"]) ->
        "#{Config.settings!().tracker.project_identifier}-#{work_item["sequence_id"]}"

      is_integer(work_item["sequence_id"]) ->
        "PLANE-#{work_item["sequence_id"]}"

      true ->
        work_item["id"]
    end
  end

  defp work_item_url(%{"url" => url}) when is_binary(url), do: url

  defp work_item_url(work_item) do
    tracker = Config.settings!().tracker

    if is_integer(work_item["sequence_id"]) do
      "#{endpoint()}/#{tracker.workspace_slug}/projects/#{tracker.project_id}/issues/#{work_item["sequence_id"]}"
    end
  end

  defp map_value(map, key) do
    case map[key] do
      value when is_map(value) -> value
      value -> value
    end
  end

  defp map_list(map, key) do
    case map[key] do
      values when is_list(values) -> values
      _ -> []
    end
  end

  defp resolve_state(%{} = state, _state_index), do: state
  defp resolve_state(state_id, state_index) when is_binary(state_id), do: Map.get(state_index, state_id)
  defp resolve_state(_state, _state_index), do: nil

  defp label_names(labels) do
    labels
    |> Enum.flat_map(fn
      %{"name" => name} when is_binary(name) -> [String.downcase(name)]
      name when is_binary(name) -> [String.downcase(name)]
      _ -> []
    end)
  end

  defp assignee_ids(assignees) do
    Enum.flat_map(assignees, fn
      %{"id" => id} when is_binary(id) -> [id]
      id when is_binary(id) -> [id]
      _ -> []
    end)
  end

  defp assigned_to_worker?(_assignees, nil), do: true

  defp assigned_to_worker?(assignees, %{match_values: match_values}) do
    assignees
    |> Enum.any?(fn assignee ->
      assignee
      |> assignee_match_values()
      |> Enum.any?(&MapSet.member?(match_values, &1))
    end)
  end

  defp assignee_match_values(%{} = assignee) do
    [assignee["id"], assignee["email"], assignee["display_name"]]
    |> Enum.map(&normalize_assignee_match_value/1)
    |> Enum.reject(&is_nil/1)
  end

  defp assignee_match_values(value), do: [normalize_assignee_match_value(value)] |> Enum.reject(&is_nil/1)

  defp routing_assignee_filter do
    case Config.settings!().tracker.assignee do
      nil ->
        {:ok, nil}

      assignee ->
        case normalize_assignee_match_value(assignee) do
          nil -> {:ok, nil}
          normalized -> {:ok, %{configured_assignee: assignee, match_values: MapSet.new([normalized])}}
        end
    end
  end

  defp normalize_assignee_match_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_assignee_match_value(_value), do: nil

  defp list_payload(%{"results" => results}) when is_list(results), do: results
  defp list_payload(%{"items" => items}) when is_list(items), do: items
  defp list_payload(values) when is_list(values), do: values
  defp list_payload(_body), do: []

  defp uniq_issues(issues) do
    issues
    |> Enum.reduce({MapSet.new(), []}, fn
      %Issue{id: id} = issue, {seen, acc} when is_binary(id) ->
        if MapSet.member?(seen, id), do: {seen, acc}, else: {MapSet.put(seen, id), [issue | acc]}

      _issue, state ->
        state
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp plane_status_error(message, response) do
    Logger.error("#{message} status=#{response.status} body=#{summarize_error_body(response.body)}")
    {:error, {:plane_api_status, response.status}}
  end

  defp plane_request_error(reason) do
    Logger.error("Plane API request failed: #{inspect(reason)}")
    {:error, {:plane_api_request, reason}}
  end

  defp summarize_error_body(body) when is_binary(body) do
    body
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> truncate_error_body()
    |> inspect()
  end

  defp summarize_error_body(body) do
    body
    |> inspect(limit: 20, printable_limit: @max_error_body_log_bytes)
    |> truncate_error_body()
  end

  defp truncate_error_body(body) when is_binary(body) do
    if byte_size(body) > @max_error_body_log_bytes do
      binary_part(body, 0, @max_error_body_log_bytes) <> "...<truncated>"
    else
      body
    end
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(raw) do
    case DateTime.from_iso8601(raw) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp parse_priority("urgent"), do: 1
  defp parse_priority("high"), do: 2
  defp parse_priority("medium"), do: 3
  defp parse_priority("low"), do: 4
  defp parse_priority(_priority), do: nil

  defp strip_html(nil), do: nil

  defp strip_html(html) when is_binary(html) do
    html
    |> String.replace(~r/<[^>]*>/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp html_escape(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
    |> String.replace("\n", "<br>")
  end

  defp normalize_name(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_name(value), do: value |> to_string() |> normalize_name()
end
