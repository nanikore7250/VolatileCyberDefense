# VolatileCyberDefense (VCD)

> **A new security paradigm: systems that intentionally self-destruct upon attack detection, preserve forensic evidence before dying, and recover clean.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Status: Proof of Concept](https://img.shields.io/badge/Status-Proof%20of%20Concept-blue)]()
[![Python](https://img.shields.io/badge/Python-3.x-green)]()

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
| ③ Self-Destruct | `os._exit(1)` | Eliminate contaminated state |
| ④ Recover | Supervisor auto-restarts process | Return to clean state |
| ⑤ Block | Load blocklist on startup | Prevent re-entry from same source |

The key insight: **the attacker never gets to operate in a contaminated state, and they cannot erase their tracks because the evidence was already sent before the process died.**

---

## Multi-Layer Volatility

VCD is designed as a layered architecture, where each layer handles failures the layer below cannot recover from:

```
L1: Process Layer  (Elixir/OTP Supervisor)   — milliseconds
L2: Container Layer (Kubernetes Pod)          — seconds
L3: Node Layer      (Kubernetes Cluster)      — minutes
```

This PoC demonstrates **L1** — process-level volatility in Python.
Full implementation targeting Elixir + Kubernetes is planned.

---

## Comparison with Existing Paradigms

| Paradigm | Primary Goal | On Breach | Forensics | State |
|----------|-------------|-----------|-----------|-------|
| Defense in Depth | Prevent intrusion | Exception | Post-incident | Maintained |
| Zero Trust | Strengthen auth | Exception | Post-incident | Maintained |
| DFIR | Investigate after | React after | Post-collection | Recovery goal |
| **VCD** | **Eliminate contamination** | **Designed action** | **Self-reported before death** | **Intentionally discarded** |

---

## This Proof of Concept

### What it demonstrates

A minimal Flask application that:
1. Detects XSS and SQL injection patterns in user input
2. Writes forensic evidence to an append-only file before dying
3. Calls `os._exit(1)` to immediately terminate the process
4. Is restarted automatically by `supervisord`
5. Loads the blocklist on startup to reject the attacker's IP

### Structure

```
VolatileCyberDefense/
├── app.py              # Flask app with VCD behavior
├── forensics.jsonl     # Append-only forensic log (survives process death)
├── vcd.conf            # supervisord config for auto-restart
└── README.md
```

### app.py

```python
from flask import Flask, request
import os
import json
from datetime import datetime
import re

XSS_PATTERN = re.compile(r"<script|alert\(|onerror=", re.IGNORECASE)
SQLI_PATTERN = re.compile(r"(\bOR\b|\bAND\b|--|;|'|\bUNION\b)", re.IGNORECASE)

app = Flask(__name__)
BLOCKLIST = set()

def send_forensics(reason, request):
    evidence = {
        "timestamp": datetime.utcnow().isoformat(),
        "reason": reason,
        "ip": request.remote_addr,
        "payload": request.form.get("username"),
        "headers": dict(request.headers)
    }
    with open("/root/VolatileCyberDefense/forensics.jsonl", "a") as f:
        f.write(json.dumps(evidence) + "\n")

def load_blocklist():
    try:
        with open("/root/VolatileCyberDefense/forensics.jsonl") as f:
            for line in f:
                evidence = json.loads(line)
                BLOCKLIST.add(evidence["ip"])
    except FileNotFoundError:
        pass

@app.before_request
def check_blocklist():
    if request.remote_addr in BLOCKLIST:
        return "blocked", 403

@app.route('/welcome', methods=['POST'])
def welcome():
    username = request.form["username"]
    if XSS_PATTERN.search(username) or SQLI_PATTERN.search(username):
        send_forensics("XSS or SQL injection attack detected", request)
        os._exit(1)
    return "ようこそ、" + username + "さん"

@app.route('/')
def index():
    return """
    <form action="/welcome" method="POST">
        <input type="text" name="username" placeholder="Your name"><br />
        <input type="submit" value="login">
    </form>
    """

load_blocklist()
app.run(port=5000)
```

### supervisord config

```ini
[program:volatile]
command=/root/VolatileCyberDefense/venv/bin/python /root/VolatileCyberDefense/app.py
autostart=true
autorestart=true
stopsignal=QUIT
stdout_logfile=/var/log/supervisor/volatile-app.log
stderr_logfile=/var/log/supervisor/volatile-err.log
```

### Forensic output example

```json
{
  "timestamp": "2026-04-16T10:23:45.123456",
  "reason": "XSS or SQL injection attack detected",
  "ip": "192.168.1.100",
  "payload": "<script>alert('xss')</script>",
  "headers": { "User-Agent": "...", "Content-Type": "..." }
}
```

---

## Getting Started

```bash
git clone https://github.com/nanikore7250/VolatileCyberDefense.git
cd VolatileCyberDefense
pip install flask
supervisord -c vcd.conf
```

Visit `http://localhost:5000` and try submitting a normal name, then an attack payload.

---

## Roadmap

| Phase | Language | Target | Status |
|-------|----------|--------|--------|
| Phase 1 | Python | Concept validation | ✅ Complete |
| Phase 2 | Elixir / OTP | Process-level volatility with Supervisor trees | 🔲 Planned |
| Phase 3 | Elixir + Kubernetes | Multi-layer volatility (L1–L3) | 🔲 Planned |
| Phase 4 | — | arXiv paper + OSS release | 🔲 Planned |

---

## Known Limitations of this PoC

- Pattern matching is naive (regex-based, not semantic)
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

Pythonで実装した最小構成のPoCであり、以下の5ステップが一連の流れとして動作することを示す：

1. XSS・SQLiパターンの検知
2. プロセス終了前にフォレンジック情報をファイルへ書き出し
3. `os._exit(1)` による即時自壊
4. `supervisord` による自動再起動
5. 起動時にブロックリストを読み込み、同一IPを403で拒否

---

## ロードマップ

| フェーズ | 言語 | 目標 |
|---------|------|------|
| Phase 1 | Python | 概念実証 ✅ |
| Phase 2 | Elixir / OTP | Supervisorツリーによるプロセスレベル揮発性 |
| Phase 3 | Elixir + Kubernetes | L1〜L3の多段揮発性の完成 |
| Phase 4 | — | arXiv論文 + OSS公開 |
