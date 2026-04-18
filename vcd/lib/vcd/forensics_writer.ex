defmodule VCD.ForensicsWriter do
  require Logger

  @forensics_path Application.compile_env(:vcd, :forensics_path, "/var/vcd/forensics.jsonl")

  def write_and_die(evidence) do
    entry =
      evidence
      |> Map.put(:timestamp, DateTime.utc_now() |> DateTime.to_iso8601())
      |> Map.put(:vm, capture_vm_info())
      |> Jason.encode!()

    path = @forensics_path
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, entry <> "\n", [:append])

    Logger.warning("[VCD] Attack detected — evidence saved, process exiting")

    if Application.get_env(:vcd, :debug, false) do
      VCD.BlockList.clear()
    end

    exit(:attack_detected)
  end

  defp capture_vm_info do
    pid = self()

    proc =
      Process.info(pid, [
        :memory,
        :message_queue_len,
        :reductions,
        :current_function,
        :current_stacktrace,
        :registered_name,
        :status
      ]) || []

    %{
      pid: inspect(pid),
      node: inspect(node()),
      process_count: :erlang.system_info(:process_count),
      memory: format_memory(:erlang.memory()),
      scheduler_id: :erlang.system_info(:scheduler_id),
      process: %{
        memory_bytes: proc[:memory],
        message_queue_len: proc[:message_queue_len],
        reductions: proc[:reductions],
        status: inspect(proc[:status]),
        registered_name: inspect(proc[:registered_name]),
        current_function: format_mfa(proc[:current_function]),
        stacktrace: format_stacktrace(proc[:current_stacktrace] || [])
      }
    }
  end

  defp format_mfa({m, f, a}), do: "#{m}.#{f}/#{a}"
  defp format_mfa(other), do: inspect(other)

  defp format_stacktrace(frames) do
    Enum.map(frames, fn
      {m, f, a, info} ->
        location =
          case {info[:file], info[:line]} do
            {nil, _} -> ""
            {file, line} -> " (#{file}:#{line})"
          end

        "#{m}.#{f}/#{a}#{location}"

      {m, f, a} ->
        "#{m}.#{f}/#{a}"
    end)
  end

  defp format_memory(mem) do
    Map.new(mem, fn {k, v} -> {k, v} end)
  end
end
