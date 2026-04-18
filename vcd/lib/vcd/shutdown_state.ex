defmodule VCD.ShutdownState do
  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, false, name: __MODULE__)
  end

  def shutting_down? do
    GenServer.call(__MODULE__, :shutting_down?)
  end

  # L1のみ — プロセス自壊、コンテナは継続
  def process_only do
    GenServer.cast(__MODULE__, :process_only)
  end

  # L1 + L2 — プロセス自壊後にコンテナも終了させる
  def container_shutdown do
    GenServer.cast(__MODULE__, :container_shutdown)
  end

  # GenServer callbacks

  @impl true
  def init(_) do
    {:ok, %{shutting_down: false}}
  end

  @impl true
  def handle_call(:shutting_down?, _from, state) do
    {:reply, state.shutting_down, state}
  end

  @impl true
  def handle_cast(:process_only, state) do
    Logger.info("[VCD] Severity: low — L1 self-destruct only, container continues")
    {:noreply, state}
  end

  @impl true
  def handle_cast(:container_shutdown, state) do
    Logger.warning("[VCD] Severity: high — initiating Graceful Volatile Shutdown (L2)")
    schedule_graceful_shutdown()
    {:noreply, %{state | shutting_down: true}}
  end

  # Readiness Probe が 503 を返し始め、k8s がトラフィックを切り離した後に
  # シャットダウンを完了させるため、設定された timeout_ms だけ待ってから終了する
  defp schedule_graceful_shutdown do
    cfg = Application.get_env(:vcd, :shutdown, [])
    mode = Keyword.get(cfg, :mode, :graceful)
    timeout_ms = Keyword.get(cfg, :timeout_ms, 5_000)

    case mode do
      :strict ->
        Logger.warning("[VCD] Shutdown mode: strict — terminating immediately")
        System.stop(0)

      :graceful ->
        Logger.warning("[VCD] Shutdown mode: graceful — waiting for in-flight requests")
        Process.send_after(self(), :do_shutdown, timeout_ms)

      :timeout ->
        Logger.warning("[VCD] Shutdown mode: timeout — waiting #{timeout_ms}ms")
        Process.send_after(self(), :do_shutdown, timeout_ms)
    end
  end

  @impl true
  def handle_info(:do_shutdown, state) do
    Logger.warning("[VCD] Graceful Volatile Shutdown complete — stopping VM")
    System.stop(0)
    {:noreply, state}
  end
end
