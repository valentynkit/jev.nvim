// Record and replay proxy. Keys every request by sha256 of state plus questions, the
// way research/01 section 4 describes, and writes fixtures/recorded/<hash>.json.
//
//   JEV_UPSTREAM=http://127.0.0.1:4322 node tools/proxy.js   # record (costs money)
//   node tools/proxy.js                                      # replay only, free
//
// Replayed bodies carry recorded_latency_ms, so the measurement reports the latency the
// real endpoint gave rather than the microseconds this proxy takes.
const http = require("http");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const dir = process.env.JEV_RECORDINGS ||
  path.join(__dirname, "..", "fixtures", "recorded");
const upstream = process.env.JEV_UPSTREAM || "";
const port = Number(process.env.JEV_PROXY_PORT || 4373);
const stats = { hits: 0, misses: 0, recorded: 0, errors: 0, upstream: upstream || null };

const canon = (v) => {
  if (Array.isArray(v)) return "[" + v.map(canon).join(",") + "]";
  if (v && typeof v === "object") {
    return "{" + Object.keys(v).sort().map((k) => JSON.stringify(k) + ":" + canon(v[k])).join(",") + "}";
  }
  return JSON.stringify(v === undefined ? null : v);
};

// Model is left out of the key on purpose: the same state and questions should replay
// across a model rename (the gateway shim answers as typesafe-ai/jev, not jev-1.13.0).
const keyFor = (body) =>
  crypto.createHash("sha256")
    .update(canon({ state: body.state, questions: body.questions }))
    .digest("hex");

const send = (res, code, obj) => {
  res.writeHead(code, { "Content-Type": "application/json" });
  res.end(JSON.stringify(obj));
};

http
  .createServer((req, res) => {
    let raw = "";
    req.on("data", (c) => (raw += c));
    req.on("end", async () => {
      if (req.url.startsWith("/_stats")) return send(res, 200, stats);

      let body;
      try {
        body = JSON.parse(raw || "{}");
      } catch {
        return send(res, 400, { detail: "malformed JSON" });
      }
      const file = path.join(dir, keyFor(body) + ".json");
      if (fs.existsSync(file)) {
        stats.hits += 1;
        return send(res, 200, JSON.parse(fs.readFileSync(file, "utf8")));
      }
      stats.misses += 1;
      if (!upstream) {
        return send(res, 503, {
          detail: "no recording for this request; run `make record` once with a key",
        });
      }

      const started = Date.now();
      try {
        const up = await fetch(upstream.replace(/\/+$/, "") + "/v1/systemone", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            ...(process.env.TYPESAFE_API_KEY
              ? { Authorization: `Bearer ${process.env.TYPESAFE_API_KEY}` }
              : {}),
          },
          body: raw,
        });
        const text = await up.text();
        if (!up.ok) {
          stats.errors += 1;
          const retry = up.headers.get("retry-after");
          res.writeHead(up.status, {
            "Content-Type": "application/json",
            ...(retry ? { "retry-after": retry } : {}),
          });
          return res.end(text);
        }
        const answer = JSON.parse(text);
        answer.recorded_latency_ms = Date.now() - started;
        fs.mkdirSync(dir, { recursive: true });
        fs.writeFileSync(file, JSON.stringify(answer, null, 2) + "\n");
        stats.recorded += 1;
        send(res, 200, answer);
      } catch (err) {
        stats.errors += 1;
        send(res, 502, { detail: String(err) });
      }
    });
  })
  .listen(port, "127.0.0.1");
