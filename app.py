from flask import Flask, request
import os
import json
from datetime import datetime
import re

# 簡単な攻撃パターンを定義
XSS_PATTERN = re.compile(r"<script|alert\(|onerror=", re.IGNORECASE)
SQLI_PATTERN = re.compile(r"(\bOR\b|\bAND\b|--|;|'|\bUNION\b)", re.IGNORECASE)

app = Flask(__name__)
BLOCKLIST = set()  # 本来はRedis等の外部に持つ

# 起動時にブロックリストをロードする
def load_blocklist():
    try:
        with open("/root/VolatileCyberDefense/forensics.jsonl") as f:
            for line in f:
                evidence = json.loads(line)
                BLOCKLIST.add(evidence["ip"])
    except FileNotFoundError:
        pass


# 攻撃を検知したら証拠を残す関数
def send_forensics(reason, request):
    evidence = {
        "timestamp": datetime.utcnow().isoformat(),
        "reason": reason,
        "ip": request.remote_addr,
        "payload": request.form.get("username"),
        "headers": dict(request.headers)
    }
    # プロセスが死んでも残る場所に書く
    with open("/root/VolatileCyberDefense/forensics.jsonl", "a") as f:
        f.write(json.dumps(evidence) + "\n")

# 攻撃を検知したら情報を出力してプロセスを終了する
def get_injection():
    username = request.form["username"]
    if XSS_PATTERN.search(username) or SQLI_PATTERN.search(username):
        send_forensics("XSS or SQL injection attack detected", request)
        os._exit(1)
    return request.form["username"]

# ブロックリストに入っているIPは403で返す
@app.before_request
def check_blocklist():
    if request.remote_addr in BLOCKLIST:
        return "blocked", 403

# 通常時は接続できる
@app.route('/welcome', methods=['POST'])
def welcome():
    return "ようこそ、" + get_injection() + "さん"

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