from flask import Flask, request, jsonify
import time

app = Flask(__name__)

REQUEST_LOG = []


@app.route("/", methods=["GET"])
def index():
    return jsonify({"status": "ok", "service": "phase4-target-app"})


@app.route("/api/data", methods=["GET", "POST"])
def data():
    entry = {
        "timestamp": time.time(),
        "method": request.method,
        "remote_addr": request.remote_addr,
        "args": request.args.to_dict(),
        "json": request.get_json(silent=True),
    }
    REQUEST_LOG.append(entry)
    return jsonify({"message": "received", "entry": entry})


@app.route("/api/log", methods=["GET"])
def log():
    return jsonify({"count": len(REQUEST_LOG), "entries": REQUEST_LOG[-20:]})


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "healthy"})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
