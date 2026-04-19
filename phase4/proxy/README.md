# Phase 4 Proxy

Elixir製のシンプルなリバースプロキシ。  
すべてのリクエストをそのままアップストリームのFlaskアプリへ転送する。

```
Internet → Elixir Proxy :4000 → Flask App :5000
```

## 起動方法

### 1. Flaskアプリを起動

```bash
cd ../app
source ../../venv/bin/activate
python app.py
```

### 2. Elixirプロキシを起動

```bash
cd phase4/proxy
mix deps.get
mix run --no-halt
```

デフォルトでポート4000で待ち受け、`http://localhost:5000` へ転送する。

## 環境変数

| 変数名 | デフォルト | 説明 |
|---|---|---|
| `PROXY_PORT` | `4000` | プロキシの待ち受けポート |
| `UPSTREAM_URL` | `http://localhost:5000` | 転送先URL |

```bash
PROXY_PORT=8080 UPSTREAM_URL=http://flask-app:5000 mix run --no-halt
```

## 動作確認

```bash
# プロキシ経由でFlaskにアクセス
curl http://localhost:4000/
curl http://localhost:4000/health
curl -X POST http://localhost:4000/api/data \
  -H "Content-Type: application/json" \
  -d '{"hello": "world"}'
curl http://localhost:4000/api/log
```

## ファイル構成

```
phase4/proxy/
├── config/config.exs       # ポート・アップストリームURL設定
├── lib/proxy/
│   ├── application.ex      # Cowboyサーバー起動
│   └── router.ex           # リクエスト転送ロジック
└── mix.exs                 # 依存: plug_cowboy, req
```
