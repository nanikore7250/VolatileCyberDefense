defmodule VCD.Validator do
  @xss_patterns [
    ~r/<script/i,
    ~r/javascript:/i,
    ~r/on\w+\s*=/i,
    ~r/<iframe/i,
    ~r/eval\s*\(/i
  ]

  @sqli_patterns [
    ~r/(\s|^)(SELECT|INSERT|UPDATE|DELETE|DROP|UNION|ALTER)\s/i,
    ~r/'.*--/,
    ~r/;\s*(DROP|DELETE|UPDATE|INSERT)/i,
    ~r/'\s*OR\s*'?\d/i,
    ~r/\/\*.*\*\//
  ]

  @all_patterns @xss_patterns ++ @sqli_patterns

  @doc """
  Returns {:attack, pattern} if any input matches, :ok otherwise.
  Checks all inputs in parallel.
  """
  def validate(inputs) when is_list(inputs) do
    inputs
    |> Task.async_stream(&check_input/1, timeout: 100, on_timeout: :kill_task)
    |> Enum.find_value(:ok, fn
      {:ok, {:attack, _} = hit} -> hit
      _ -> nil
    end)
  end

  def validate(inputs) when is_map(inputs) do
    inputs |> Map.values() |> validate()
  end

  @doc """
  Assesses severity and dispatches to the appropriate shutdown level.
  :low  → L1 only (process self-destruct, container continues)
  :high → L1 + L2 (Graceful Volatile Shutdown, container terminates)
  """
  def assess_severity(evidence) do
    ip = evidence[:ip]
    recent_count = recent_attack_count(ip)

    cond do
      recent_count >= 3 ->
        :high

      String.contains?(evidence[:pattern] || "", ["DROP", "DELETE", "INSERT", "UPDATE"]) ->
        :high

      true ->
        :low
    end
  end

  def handle_detection(evidence) do
    record_attack(evidence[:ip])
    severity = assess_severity(evidence)

    case severity do
      :low -> VCD.ShutdownState.process_only()
      :high -> VCD.ShutdownState.container_shutdown()
    end

    evidence
    |> Map.put(:severity, severity)
    |> VCD.ForensicsWriter.write_and_die()
  end

  defp check_input(value) when is_binary(value) do
    Enum.find_value(@all_patterns, :ok, fn pattern ->
      if Regex.match?(pattern, value), do: {:attack, pattern}
    end)
  end

  defp check_input(_), do: :ok

  # Simple in-memory recent attack counter using ETS
  @counter_table :vcd_attack_counter

  # Called from BlockCheck when a blocked IP attempts access again
  def record_repeat_attempt(ip) do
    record_attack(ip)
    count = recent_attack_count(ip)

    if count >= 3 and not VCD.ShutdownState.shutting_down?() do
      VCD.ShutdownState.container_shutdown()
    end
  end

  defp record_attack(ip) do
    now = System.monotonic_time(:millisecond)
    :ets.insert(@counter_table, {now, ip})
  end

  defp recent_attack_count(ip) do
    window = System.monotonic_time(:millisecond) - 60_000
    :ets.tab2list(@counter_table)
    |> Enum.count(fn {ts, stored_ip} -> stored_ip == ip && ts > window end)
  rescue
    _ -> 0
  end
end
