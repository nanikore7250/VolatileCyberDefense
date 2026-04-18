# VCD Phase3 実装引継ぎ — Claude Code向け

## リポジトリ

https://github.com/nanikore7250/VolatileCyberDefense  
ブランチ：`phase3/k8s`を新規作成して作業すること

---

## Phase3の目標

**Elixir（Phase2）+ Kubernetes の統合による多段揮発性の完成**

- L1（プロセス）: Phase2で実装済み
- L2（コンテナ）: Graceful Volatile Shutdown の実装 ← **今回のメイン**
- L3（ノード）: Kubernetesが自律的に処理（実装不要）

---

## Phase2の実装（前提知識）

```
vcd/
├── mix.exs
├── config/
│   ├── dev.exs
│   └── prod.exs
└── lib/vcd/
    ├── application.ex       # OTP Application — Supervisorの起動
    ├── block_list.ex        # GenServer + ETS ブロックリスト
    ├── validator.ex         # Task.async_stream による並列検査
    ├── forensics_writer.ex  # 証拠書き込み → exit(:attack_detected)
    ├── router.ex            # Plug.Router
    └── plugs/
        ├── block_check.ex   # ブロックリスト確認（403）
        └── attack_detect.ex # 検知 → 自壊フロー制御
```

---

## Phase3で実装するもの

### 1. ShutdownState（GenServer）

自壊レベルを管理するGenServer。深刻度に応じてL1のみかL2まで進むかを制御する。

```elixir
defmodule VCD.ShutdownState do
  use GenServer

  # プロセス自壊のみ（コンテナは継続）
  def process_only(), do: GenServer.cast(__MODULE__, :process_only)

  # Graceful Volatile Shutdown開始（コンテナレベルの自壊）
  def container_shutdown(), do: GenServer.cast(__MODULE__, :container_shutdown)

  def shutting_down?(), do: GenServer.call(__MODULE__, :shutting_down?)
end
```

### 2. Readiness Probe エンドポイント

k8sへの通知はReadiness Probeで行う。アプリがk8s APIを直接叩かない設計。

```elixir
# router.exに追加
get "/healthz/ready" do
  if VCD.ShutdownState.shutting_down?() do
    send_resp(conn, 503, "shutting down")
  else
    send_resp(conn, 200, "ok")
  end
end

get "/healthz/live" do
  send_resp(conn, 200, "ok")
end
```

k8s側のProbe設定：
```yaml
readinessProbe:
  httpGet:
    path: /healthz/ready
    port: 4000
  periodSeconds: 5
livenessProbe:
  httpGet:
    path: /healthz/live
    port: 4000
  periodSeconds: 10
```

### 3. 深刻度による分岐（Severity-based Branching）

攻撃の深刻度に応じてL1のみで完結するかL2に進むかを分岐する。

| 深刻度 | 自壊レベル | Readiness Probe | 判断基準の例 |
|--------|-----------|----------------|------------|
| :low | L1のみ（プロセス自壊） | 変更なし（200継続） | 単発のSQLi・XSS |
| :high | L1 → L2（コンテナ自壊） | 503に切り替え | 短時間に同一IPから複数回・認証トークン異常 |

```elixir
defmodule VCD.Validator do
  def handle_detection(evidence) do
    severity = assess_severity(evidence)
    case severity do
      :low  -> VCD.ShutdownState.process_only()
      :high -> VCD.ShutdownState.container_shutdown()
    end
    VCD.ForensicsWriter.write_and_die(evidence)
  end

  defp assess_severity(evidence) do
    # 判断ロジック（今はシンプルに実装してOK）
    :low
  end
end
```

### 4. Graceful Volatile Shutdown フロー

4段階のシャットダウンシーケンス：

```
① 攻撃プロセスが即時自壊（証拠送出 → exit）
② ShutdownStateがshutting_down = trueに
③ Readiness Probeが503を返す → k8sがトラフィックを切り離す
④ 処理中リクエストが完了するのを待つ（モード設定に従う）
⑤ Podが終了 → k8sが新規Podを再生成
```

### 5. シャットダウンモード設定

```elixir
# config/prod.exs
config :vcd, :shutdown,
  mode: :graceful,   # :strict | :graceful | :timeout
  timeout_ms: 5_000  # :timeoutモード時の最大待機時間
```

| モード | 動作 |
|--------|------|
| :strict | 即時全プロセス破棄 |
| :graceful | 処理中リクエストの完了を待つ |
| :timeout | 最大N秒待って強制終了 |

`terminationGracePeriodSeconds`と連携させること。

### 6. Sidecarコンテナ（inotify監視）

フォレンジックファイルを監視してRedisに送付する。

```yaml
# k8s deployment の sidecar定義
containers:
  - name: vcd-app
    image: vcd:latest
    volumeMounts:
      - name: forensics
        mountPath: /var/vcd

  - name: vcd-sidecar
    image: vcd-sidecar:latest  # inotify + redis-cli
    volumeMounts:
      - name: forensics
        mountPath: /var/vcd
    env:
      - name: REDIS_URL
        valueFrom:
          secretKeyRef:
            name: vcd-secrets
            key: redis-url

volumes:
  - name: forensics
    emptyDir: {}
```

Sidecarの役割：
- inotifyで`/var/vcd/forensics.jsonl`の変更を検知
- 新規行をRedisに送付（`forensics`キー）
- Redisから`forensics.ip`をnetpolに連携

### 7. Redis連携のデータフロー

```
アプリ → /var/vcd/forensics.jsonl（書き込み）
Sidecar → inotify検知 → Redis送付
Redis → netpol（ブロックIP連携）
Redis → DB（永続化）

※ 逆向き通信は全て禁止
```

### 8. Kubernetes設定ファイル

以下を作成すること：

```
k8s/
├── deployment.yaml    # Pod定義（app + sidecar）
├── service.yaml       # Serviceリソース
├── networkpolicy.yaml # netpol（ブロックリスト連携）
└── configmap.yaml     # VCD設定
```

---

## Supervisor構造（Phase3完成形）

```
VCD.Application
└── VCD.Supervisor
    ├── VCD.BlockList        # GenServer + ETS
    ├── VCD.ShutdownState    # GenServer（新規追加）
    └── VCD.Endpoint         # Plug.Cowboy
```

---

## application.exへの追加

```elixir
children = [
  VCD.BlockList,
  VCD.ShutdownState,  # 追加
  {Plug.Cowboy, scheme: :http, plug: VCD.Router, options: [port: 4000]}
]
```

---

## ブランチ・実装の順序

1. `git checkout -b phase3/k8s`
2. `ShutdownState` GenServerの実装
3. Readiness Probeエンドポイントの追加
4. Validatorに深刻度判定と分岐を追加
5. シャットダウンモード設定の実装
6. k8s/ディレクトリとYAMLファイルの作成
7. Sidecarコンテナの実装
8. READMEのPhase3セクション更新

---

## 注意事項

- Readiness ProbeはHTTP 503でk8sに通知する（k8s APIは直接叩かない）
- フォレンジックファイルはemptyDirボリューム経由でSidecarと共有
- Sidecarからアプリへの逆向き通信は禁止
- `terminationGracePeriodSeconds`はshutdown timeout_msより長く設定すること

---

## 参照

- Phase1（Python PoC）: https://github.com/nanikore7250/VolatileCyberDefense/tree/phase1/python
- Phase2（Elixir）: https://github.com/nanikore7250/VolatileCyberDefense/tree/phase2/elixir
- コンセプトドキュメント: VCD_concept_v2.docx（リポジトリ内）
