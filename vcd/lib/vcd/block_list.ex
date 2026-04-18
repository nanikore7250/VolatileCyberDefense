defmodule VCD.BlockList do
  use GenServer
  require Logger

  @table :vcd_blocklist

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def blocked?(ip) do
    :ets.member(@table, ip)
  end

  def block(ip) do
    GenServer.cast(__MODULE__, {:block, ip})
  end

  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  # GenServer callbacks

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    load_persistent_blocks()
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:block, ip}, state) do
    :ets.insert(@table, {ip, true})
    persist_block(ip)
    Logger.warning("[VCD] Blocked IP: #{inspect(ip)}")
    {:noreply, state}
  end

  @impl true
  def handle_call(:clear, _from, state) do
    :ets.delete_all_objects(@table)
    File.rm(blocklist_path())
    Logger.warning("[VCD] Blocklist cleared (debug mode)")
    {:reply, :ok, state}
  end

  defp blocklist_path, do: Application.get_env(:vcd, :blocklist_path, "/var/vcd/blocklist.txt")

  defp load_persistent_blocks do
    path = blocklist_path()

    case File.read(path) do
      {:ok, content} ->
        content
        |> String.split("\n", trim: true)
        |> Enum.each(fn ip -> :ets.insert(@table, {ip, true}) end)

      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        Logger.warning("[VCD] Could not load blocklist: #{inspect(reason)}")
    end
  end

  defp persist_block(ip) do
    path = blocklist_path()
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, ip <> "\n", [:append])
  end
end
