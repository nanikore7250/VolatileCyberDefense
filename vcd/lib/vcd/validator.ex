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
  Returns {:attack, pattern_description} if any input matches an attack pattern,
  :ok otherwise. Checks all inputs in parallel.
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
    inputs
    |> Map.values()
    |> validate()
  end

  defp check_input(value) when is_binary(value) do
    Enum.find_value(@all_patterns, :ok, fn pattern ->
      if Regex.match?(pattern, value) do
        {:attack, pattern}
      end
    end)
  end

  defp check_input(_), do: :ok
end
