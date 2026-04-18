defmodule VCD.Router do
  use Plug.Router
  import Plug.Conn

  plug VCD.Plugs.BlockCheck
  plug :match
  plug Plug.Parsers,
    parsers: [:urlencoded, :json],
    pass: ["*/*"],
    json_decoder: Jason
  plug VCD.Plugs.AttackDetect
  plug :dispatch

  # Health check endpoints — must be before BlockCheck/AttackDetect in the pipeline,
  # so they are placed outside the plug pipeline using forward or raw match.
  # These routes bypass BlockCheck intentionally: k8s probes must always reach them.
  get "/healthz/live" do
    send_resp(conn, 200, "ok")
  end

  get "/healthz/ready" do
    if VCD.ShutdownState.shutting_down?() do
      send_resp(conn, 503, "shutting down")
    else
      send_resp(conn, 200, "ok")
    end
  end

  get "/" do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, index_html())
  end

  post "/welcome" do
    username = conn.params["username"] || ""

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, welcome_html(username))
  end

  match _ do
    send_resp(conn, 404, "Not Found")
  end

  defp index_html do
    """
    <!DOCTYPE html>
    <html lang="ja">
    <head>
      <meta charset="UTF-8">
      <title>VCD Phase 2 — Demo</title>
      <style>
        body { font-family: monospace; max-width: 640px; margin: 60px auto; background: #0d1117; color: #c9d1d9; }
        h1 { color: #58a6ff; }
        .subtitle { color: #8b949e; margin-bottom: 2em; }
        label { display: block; margin-bottom: 6px; color: #8b949e; }
        input[type=text] {
          width: 100%; padding: 10px; box-sizing: border-box;
          background: #161b22; border: 1px solid #30363d; color: #c9d1d9;
          border-radius: 4px; font-family: monospace; font-size: 14px;
        }
        button {
          margin-top: 12px; padding: 10px 24px;
          background: #238636; color: #fff; border: none;
          border-radius: 4px; cursor: pointer; font-size: 14px;
        }
        button:hover { background: #2ea043; }
        .hint { margin-top: 2em; padding: 12px; background: #161b22; border: 1px solid #30363d; border-radius: 4px; }
        .hint p { margin: 4px 0; color: #8b949e; font-size: 13px; }
        .hint code { color: #ff7b72; }
      </style>
    </head>
    <body>
      <h1>⚡ Volatile Cyber Defense</h1>
      <p class="subtitle">Phase 2 — Elixir / OTP Demo</p>

      <form action="/welcome" method="POST">
        <label for="username">ユーザー名</label>
        <input type="text" id="username" name="username" placeholder="名前を入力してください" autofocus>
        <button type="submit">ログイン</button>
      </form>

      <div class="hint">
        <p>通常入力 → 正常応答</p>
        <p>攻撃ペイロードを試す：</p>
        <p><code>&lt;script&gt;alert(1)&lt;/script&gt;</code> — XSS</p>
        <p><code>' OR '1'='1</code> — SQLi</p>
        <p>検知されるとプロセスが即時自壊し、同じIPは以降 403 で拒否されます。</p>
      </div>
    </body>
    </html>
    """
  end

  defp welcome_html(username) do
    """
    <!DOCTYPE html>
    <html lang="ja">
    <head>
      <meta charset="UTF-8">
      <title>VCD — ようこそ</title>
      <style>
        body { font-family: monospace; max-width: 640px; margin: 60px auto; background: #0d1117; color: #c9d1d9; }
        h1 { color: #3fb950; }
        a { color: #58a6ff; }
      </style>
    </head>
    <body>
      <h1>✓ ようこそ、#{username}さん</h1>
      <p>攻撃は検知されませんでした。</p>
      <p><a href="/">← 戻る</a></p>
    </body>
    </html>
    """
  end
end
