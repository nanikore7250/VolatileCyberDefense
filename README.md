# VolatileCyberDefense (VCD)

> **A new security paradigm: systems that intentionally self-destruct upon attack detection, preserve forensic evidence before dying, and recover clean.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Status: Proof of Concept](https://img.shields.io/badge/Status-Proof%20of%20Concept-blue)]()
[![Elixir](https://img.shields.io/badge/Elixir-1.19-purple)]()

---

## What is Volatile Cyber Defense?

Traditional security assumes systems should **survive attacks** — detect, block, and continue.

VCD takes the opposite approach:

> **When an attack is detected, the process intentionally kills itself — but not before preserving forensic evidence. It then recovers in a clean state, with the attacker's source blocked.**

This is inspired by the **"Let it crash"** philosophy of Erlang/OTP and Kubernetes' self-healing architecture, applied as a security primitive.

---

## The Problem with Traditional Security

```
Attack → Detect → Block → Continue (contaminated state persists)
```

When an attacker breaches the first layer of defense, the **contaminated state remains in memory**. The attacker can use this to:
- Perform lateral movement
- Persist long-term in the system
- Cover their tracks at leisure

---

## The VCD Approach

```
Attack → Detect → Preserve Evidence → Self-Destruct → Recover Clean → Block Source
```

| Phase | Action | Purpose |
|-------|--------|---------|
| ① Detect | Pattern match on request | Identify attack before damage |
| ② Forensics | Write evidence to external storage | Preserve proof before dying |
| ③ Self-Destruct | `exit(:attack_detected)` | Eliminate contaminated state |
| ④ Recover | OTP Supervisor auto-restarts process | Return to clean state |
| ⑤ Block | ETS-backed blocklist survives restart | Prevent re-entry from same source |

The key insight: **the attacker never gets to operate in a contaminated state, and they cannot erase their tracks because the evidence was already sent before the process died.**

---

## Multi-Layer Volatility

VCD is designed as a layered architecture, where each layer handles failures the layer below cannot recover from:

```
L1: Process Layer  (Elixir/OTP Supervisor)   — milliseconds
L2: Container Layer (Kubernetes Pod)          — seconds
L3: Node Layer      (Kubernetes Cluster)      — minutes
```

This implementation demonstrates **L1** — process-level volatility with Elixir/OTP.
Full multi-layer implementation targeting Elixir + Kubernetes is planned.

---

## Comparison with Existing Paradigms

| Paradigm | Primary Goal | On Breach | Forensics | State |
|----------|-------------|-----------|-----------|-------|
| Defense in Depth | Prevent intrusion | Exception | Post-incident | Maintained |
| Zero Trust | Strengthen auth | Exception | Post-incident | Maintained |
| DFIR | Investigate after | React after | Post-collection | Recovery goal |
| **VCD** | **Eliminate contamination** | **Designed action** | **Self-reported before death** | **Intentionally discarded** |

---

## Implementation — Elixir / OTP

### Structure

```
vcd/
├── mix.exs
├── config/
│   ├── dev.exs     # debug: true
│   └── prod.exs    # debug: false
└── lib/vcd/
    ├── application.ex          # OTP Application — starts Supervisor
    ├── block_list.ex           # GenServer + ETS blocklist (survives restarts)
    ├── validator.ex            # Parallel attack detection (Task.async_stream)
    ├── forensics_writer.ex     # Write evidence → exit(:attack_detected)
    ├── router.ex               # Plug.Router + demo form
    └── plugs/
        ├── block_check.ex      # Reject blocked IPs (403)
        └── attack_detect.ex    # Detect attack → forensics → self-destruct
```

### Supervisor tree

```
Vcd.Application
└── Vcd.Supervisor (one_for_one)
    ├── VCD.BlockList     ← GenServer + ETS; persists blocklist across restarts
    └── VCD.Router        ← Plug.Cowboy HTTP server
```

### Key design points

- **ETS-backed blocklist**: stored outside the Cowboy process, so a worker crash does not clear it — blocked IPs stay blocked across supervisor restarts.
- **Parallel input inspection**: `Task.async_stream` checks all request parameters simultaneously with a 100 ms timeout.
- **Minimal critical path**: `ForensicsWriter.write_and_die/1` does exactly two things — append a JSON line, then `exit(:attack_detected)`. No RPC, no HTTP call.
- **Separation of concerns**: writing evidence and restarting are decoupled. The Supervisor handles recovery; the dying process only needs to flush to disk.
- **VM forensics**: at the moment of self-destruct, process memory, reductions, message queue length, and full stacktrace are captured and written to the forensic log.

### Getting Started

```bash
git clone https://github.com/nanikore7250/VolatileCyberDefense.git
cd VolatileCyberDefense/vcd
mix deps.get
mix run --no-halt        # dev mode (default)
MIX_ENV=prod mix run --no-halt  # production mode
```

Open `http://localhost:4000` in a browser to use the demo form.

### Debug mode

| `MIX_ENV` | Blocklist after self-destruct |
|-----------|-------------------------------|
| `dev` (default) | **Cleared** — same IP can reconnect immediately |
| `prod` | **Persisted** — same IP stays blocked across restarts |

In debug mode, `ForensicsWriter` calls `BlockList.clear()` before `exit(:attack_detected)`, wiping both the ETS table and the on-disk `blocklist.txt`. This lets you trigger the full VCD cycle repeatedly without manually resetting state.

### Attack simulation

```bash
# Normal request
curl http://localhost:4000/

# XSS attack — triggers forensics write + process exit + (in dev) blocklist clear
curl -X POST -d "username=<script>alert(1)</script>" http://localhost:4000/welcome

# In dev: same IP can reconnect. In prod: 403 Forbidden.
curl http://localhost:4000/

# Forensic log
cat /var/vcd/forensics.jsonl
```

### Forensic output example

```json
{
  "timestamp": "2026-04-18T04:44:34.739094Z",
  "method": "POST",
  "path": "/welcome",
  "ip": "127.0.0.1",
  "pattern": "~r/<script/i",
  "params": { "username": "<script>alert(1)</script>" },
  "vm": {
    "pid": "#PID<0.424.0>",
    "node": ":nonode@nohost",
    "process_count": 355,
    "scheduler_id": 15,
    "memory": { "total": 70476136, "processes": 16364360, "... ": "..." },
    "process": {
      "memory_bytes": 8928,
      "reductions": 4617,
      "message_queue_len": 0,
      "status": ":running",
      "stacktrace": [
        "Elixir.VCD.ForensicsWriter.write_and_die/1 (lib/vcd/forensics_writer.ex:10)",
        "Elixir.VCD.Router.plug_builder_call/2 (lib/vcd/router.ex:1)",
        "..."
      ]
    }
  }
}
```

---

## Phase 3 — Elixir + Kubernetes (L2 Container Volatility)

Phase 3 adds **Graceful Volatile Shutdown**: when a high-severity attack is detected, the container signals Kubernetes via the Readiness Probe and terminates cleanly, triggering a fresh Pod replacement.

### Multi-layer shutdown flow

```
① Attack process exits immediately  (L1 — milliseconds)
② ShutdownState sets shutting_down = true
③ /healthz/ready returns 503  →  k8s removes Pod from Service endpoints
④ In-flight requests drain  (graceful mode waits timeout_ms)
⑤ VM calls System.stop(0)  →  Pod terminates  →  k8s schedules new Pod  (L2 — seconds)
```

### Severity-based branching

| Severity | Trigger | Self-destruct level |
|----------|---------|---------------------|
| `:low` | Single XSS / SQLi | L1 only — process restarts, container continues |
| `:high` | 3+ attacks from same IP in 60s, or destructive SQL | L1 + L2 — full container replacement |

### Shutdown modes

| Mode | Behavior |
|------|----------|
| `:strict` | Terminate VM immediately |
| `:graceful` | Wait `timeout_ms` for in-flight requests, then stop |
| `:timeout` | Same as graceful — max wait then force stop |

`terminationGracePeriodSeconds` in the Deployment must exceed `timeout_ms`.

### Structure added in Phase 3

```
vcd/lib/vcd/
└── shutdown_state.ex   # GenServer — manages L2 shutdown lifecycle

k8s/
├── deployment.yaml     # Pod (vcd-app + vcd-sidecar), probes, volumes
├── service.yaml        # ClusterIP Service
├── networkpolicy.yaml  # Egress: sidecar → Redis only
└── configmap.yaml      # Shutdown mode / paths

sidecar/
├── watch.sh            # inotify → Redis forwarding script
└── Dockerfile          # alpine + inotify-tools + redis-cli
```

### Sidecar data flow

```
vcd-app  →  /var/vcd/forensics.jsonl  (emptyDir volume)
                    ↓ inotify
vcd-sidecar  →  Redis RPUSH vcd:forensics
             →  Redis SADD vcd:blocked_ips  (for netpol integration)

※ No reverse communication from sidecar to app
```

### Deploying to Kubernetes (minikube)

```bash
# Point Docker CLI to minikube's daemon
eval $(minikube docker-env)

# Build images
docker build -t vcd:latest ./vcd/
docker build -t vcd-sidecar:latest ./sidecar/

# Create Redis URL secret
kubectl create secret generic vcd-secrets \
  --from-literal=redis-url=redis://redis:6379

# Apply all resources
kubectl apply -f k8s/redis.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml

kubectl rollout status deployment/vcd-app
```

### Attack simulation (Kubernetes)

> **Note on `kubectl port-forward`**: port-forward creates a tunnel that bypasses NetworkPolicy entirely. Traffic arriving via port-forward always appears as `127.0.0.1` to the app, so the **application-layer blocklist (ETS → 403 Forbidden)** fires correctly, but the **NetworkPolicy-layer block has no effect** on port-forwarded connections. This is expected — see [Verifying NetworkPolicy blocking](#verifying-networkpolicy-blocking) below for in-cluster testing.

Forward a pod port to localhost, then run the same attack sequence:

```bash
POD=$(kubectl get pod -l app=vcd -o jsonpath='{.items[0].metadata.name}')
kubectl port-forward $POD 14000:4000
```

```bash
# Health checks
curl http://localhost:14000/healthz/live   # 200
curl http://localhost:14000/healthz/ready  # 200

# Normal request
curl -X POST -d "username=Alice" http://localhost:14000/welcome

# L1 attack (single XSS) — process restarts, container stays up
curl -X POST -d "username=<script>alert(1)</script>" http://localhost:14000/welcome
curl http://localhost:14000/healthz/ready  # still 200

# L2 escalation — blocked IP retries twice more (3 total)
# 2nd attempt: blocked with 403, attack count incremented
curl http://localhost:14000/
# 3rd attempt: blocked with 403, threshold reached → container_shutdown()
curl http://localhost:14000/

# Readiness probe flips to 503 — k8s removes pod from Service endpoints
curl http://localhost:14000/healthz/ready  # 503
curl http://localhost:14000/healthz/live   # 200 (VM still draining)

# After timeout_ms (5s prod / 2s dev): VM stops, k8s schedules fresh pods
kubectl get pods -l app=vcd
# NAME                     READY   STATUS    RESTARTS
# vcd-app-xxxxx-yyyyy      Error   ← terminated pod
# vcd-app-zzzzz-aaaaa      2/2     Running   ← new clean pod
# vcd-app-zzzzz-bbbbb      2/2     Running   ← new clean pod
```

### Verifying NetworkPolicy blocking

NetworkPolicy operates at the pod network layer and only affects traffic routed through the CNI (pod-to-pod, service-to-pod). To verify that a blocked IP is dropped at the network layer, send requests from a pod inside the cluster:

```bash
# Launch a temporary curl pod inside the cluster
kubectl run curl-test --image=curlimages/curl --restart=Never --rm -it -- sh

# Inside the pod — attack from this pod's IP
curl -X POST -d "username=<script>alert(1)</script>" http://vcd:4000/welcome
# → connection succeeds, attack detected, this pod's IP is blocked

# After SYNC_INTERVAL (30s), the NetworkPolicy is patched.
# Subsequent requests from this pod are dropped at the network layer (connection timeout),
# not rejected with 403 — the packet never reaches the app.
curl --max-time 5 http://vcd:4000/
# → curl: (28) Operation timed out  ← NetworkPolicy drop confirmed
```

Check that the NetworkPolicy was patched:

```bash
kubectl get networkpolicy vcd-block-policy \
  -o jsonpath='{.spec.ingress[0].from[0].ipBlock}' | python3 -m json.tool
# {
#   "cidr": "0.0.0.0/0",
#   "except": ["<pod-ip>/32"]
# }
```

### Unblocking IPs (for repeated testing)

After an attack, the attacker's IP is persisted in three places. Clear all three to reset state:

```bash
POD=$(kubectl get pod -l app=vcd -o jsonpath='{.items[0].metadata.name}')

# 1. Clear application-layer blocklist (ETS + blocklist.txt) via VCD.BlockList.clear/0
kubectl exec $POD -c vcd-app -- /app/_build/prod/rel/vcd/bin/vcd rpc "VCD.BlockList.clear()"

# 2. Remove IP(s) from Redis
kubectl exec $POD -c vcd-sidecar -- sh -c 'redis-cli -u "$REDIS_URL" DEL vcd:blocked_ips'

# 3. Patch NetworkPolicy to clear except[] list
kubectl patch networkpolicy vcd-block-policy --type=merge \
  -p '{"spec":{"ingress":[{"from":[{"ipBlock":{"cidr":"0.0.0.0/0","except":[]}}],"ports":[{"protocol":"TCP","port":4000}]}]}}'
```

> **Note**: Steps 2 and 3 are only needed in a Kubernetes environment. In local dev (`mix run`), blocklist is automatically cleared on self-destruct because `debug: true` is set in `dev.exs`.

---

## Roadmap

| Phase | Language | Target | Status |
|-------|----------|--------|--------|
| Phase 1 | Python | Concept validation | ✅ Complete — [see phase1/python](https://github.com/nanikore7250/VolatileCyberDefense/tree/phase1/python) |
| Phase 2 | Elixir / OTP | Process-level volatility with Supervisor trees | ✅ Complete — [see phase1/python](https://github.com/nanikore7250/VolatileCyberDefense/tree/phase2/elixir) |
| Phase 3 | Elixir + Kubernetes | Multi-layer volatility (L1–L3) | ✅ Complete |
| Phase 4 | — | arXiv paper + OSS release | 🔲 Planned |

---

## Known Limitations

- Pattern matching is regex-based, not semantic
- Blocklist is IP-based (NAT / proxies can affect innocent users)
- Forensic log is local file (should be remote/immutable in production)
- No protection against DoS via intentional false positives

These are known and intentional trade-offs for a minimal PoC. See the concept document for full discussion.

---

## Concept Document

A full concept document (in Japanese) is available: [`VCD_concept.docx`](./VCD_concept.docx)

It covers:
- Full architectural design
- Comparison with existing security paradigms
- Multi-layer volatility model
- Open research questions

---

## License

MIT

---

---

# 揮発性サイバー防御（VCD）— 日本語訳

> **攻撃を検知したらシステムが意図的に自壊し、死ぬ前に証拠を保全し、クリーンな状態で回復する——新しいセキュリティパラダイム。**

---

## 揮発性サイバー防御とは

従来のセキュリティは「攻撃に耐えて継続する」ことを前提とする。

VCDはその逆を取る：

> **攻撃を検知したら、プロセスは意図的に自壊する。ただし、死ぬ前に必ずフォレンジック証拠を外部に送出する。その後、クリーンな状態で回復し、攻撃者の接続元をブロックする。**

この思想はErlang/OTPの「Let it crash」哲学とKubernetesの自律回復機構から着想を得て、セキュリティの文脈に応用したものである。

---

## 従来モデルとの違い

従来：
```
攻撃 → 検知 → ブロック → 継続（汚染状態が残留）
```

VCD：
```
攻撃 → 検知 → 証拠送出 → 自壊 → クリーンに回復 → 接続元ブロック
```

従来モデルでは、攻撃者が第一層を突破すると「汚染された状態」がシステムに残り続ける。攻撃者はその状態を利用して横展開・長期潜伏・証拠隠滅を行う。

VCDはこれを構造的に不可能にする。プロセスが死ぬ前に証拠を外部に送出するため、攻撃者が痕跡を消す機会がない。

---

## このPoCが示すこと

Elixir / OTP で実装した最小構成のPoCであり、以下の5ステップが一連の流れとして動作することを示す：

1. XSS・SQLiパターンの並列検知（`Task.async_stream`）
2. プロセス終了前にフォレンジック情報（攻撃内容 + ErlangVM詳細）をファイルへ書き出し
3. `exit(:attack_detected)` による即時自壊
4. OTP Supervisorによる自動再起動
5. 起動後もETSテーブルにブロックリストが維持され、同一IPを403で拒否

---

## ロードマップ

| フェーズ | 言語 | 目標 |
|---------|------|------|
| Phase 1 | Python | 概念実証 ✅ |
| Phase 2 | Elixir / OTP | Supervisorツリーによるプロセスレベル揮発性 ✅ |
| Phase 3 | Elixir + Kubernetes | L1〜L3の多段揮発性の完成 ✅ |
| Phase 4 | — | arXiv論文 + OSS公開 |
