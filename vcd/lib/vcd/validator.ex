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
    severity = assess_severity(evidence)
    record_attack(evidence[:ip])

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

  defp record_attack(ip) do
    ensure_counter_table()
    now = System.monotonic_time(:second)
    :ets.insert(@counter_table, {:"#{ip}_#{now}", ip})
  end

  defp recent_attack_count(ip) do
    ensure_counter_table()
    window = System.monotonic_time(:second) - 60
    :ets.tab2list(@counter_table)
    |> Enum.count(fn {key, stored_ip} ->
      stored_ip == ip &&
        (key |> to_string() |> String.split("_") |> List.last() |> String.to_integer() > window)
    end)
  rescue
    _ -> 0
  end

  defp ensure_counter_table do
    if :ets.whereis(@counter_table) == :undefined do
      :ets.new(@counter_table, [:named_table, :bag, :public])
    end
  end
end
