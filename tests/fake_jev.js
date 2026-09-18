// Fake Jev. Answers every noul from fixtures/answers.json, so the test suite needs no
// key and no network. Shape follows research/01 section 3; the extra bits are the knobs
// the specs drive through POST /_control.
//
//   node tests/fake_jev.js            # port 4372
//   PORT=4399 node tests/fake_jev.js
//
// Knobs (env, or POST /_control with the same names):
//   fail_times     n requests answered with fail_status before a real answer
//   fail_status    429 by default
//   retry_after    value for the retry-after header on a failed request
//   max_questions  more than this many questions in one request returns
//                  400 max_tokens_exceeded, which is what drives split-on-too-big
//   max_body       same, but on request body bytes
//   delay_ms       sleep before answering
//   count_tokens   report usage.input_tokens (also FAKE_JEV_COUNT_TOKENS=1)
//   default_noul   answer for a unit missing from answers.json
const http = require("http");
const fs = require("fs");
const path = require("path");

const answersPath = process.env.FAKE_JEV_ANSWERS ||
  path.join(__dirname, "..", "fixtures", "answers.json");
const answers = JSON.parse(fs.readFileSync(answersPath, "utf8"));

const num = (v, d) => (v === undefined || v === "" ? d : Number(v));
const control = {
  fail_times: num(process.env.FAKE_JEV_FAIL_TIMES, 0),
  fail_status: num(process.env.FAKE_JEV_FAIL_STATUS, 429),
  retry_after: process.env.FAKE_JEV_RETRY_AFTER || "",
  max_questions: num(process.env.FAKE_JEV_MAX_QUESTIONS, 0),
  max_body: num(process.env.FAKE_JEV_MAX_BODY, 0),
  delay_ms: num(process.env.FAKE_JEV_DELAY_MS, 0),
  count_tokens: process.env.FAKE_JEV_COUNT_TOKENS === "1",
  default_noul: num(process.env.FAKE_JEV_DEFAULT_NOUL, 0.02),
};
const stats = { requests: 0, questions: 0, batches: [], failures: 0 };

// every units.py: 2.3 characters per token, measured against jev-latest on code+JSON
// payloads. Deliberately a different formula from the plugin's own estimator, so the
// batching spec compares two independent estimates rather than one against itself.
const countTokens = (body) => Math.ceil(body.length / 2.3);

const send = (res, code, obj, headers = {}) => {
  const out = JSON.stringify(obj);
  res.writeHead(code, { "Content-Type": "application/json", ...headers });
  res.end(out);
};

const answerFor = (q) => {
  const inst = q.instructions || {};
  const asked = typeof inst.question === "string" ? inst.question : "";
  const query = (asked.match(/"([^"]*)"/) || [])[1] || asked;
  const unit = inst.unit || {};
  const key = `${path.basename(unit.file || "")}:${unit.name || ""}`;
  const noul = ((answers[query] || {})[key]);
  return { type: "noul", noul: noul === undefined ? control.default_noul : noul };
};

http
  .createServer((req, res) => {
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => {
      if (req.url.startsWith("/_stats")) return send(res, 200, stats);
      if (req.url.startsWith("/_reset")) {
        stats.requests = 0;
        stats.questions = 0;
        stats.failures = 0;
        stats.batches = [];
        return send(res, 200, stats);
      }
      if (req.url.startsWith("/_control")) {
        Object.assign(control, JSON.parse(body || "{}"));
        return send(res, 200, control);
      }

      const finish = () => {
        stats.requests += 1;
        if (control.fail_times > 0) {
          control.fail_times -= 1;
          stats.failures += 1;
          const headers = control.retry_after ? { "retry-after": control.retry_after } : {};
          return send(res, control.fail_status, { error: "injected failure" }, headers);
        }
        let parsed;
        try {
          parsed = JSON.parse(body || "{}");
        } catch {
          return send(res, 400, { detail: "malformed JSON" });
        }
        const questions = parsed.questions || {};
        const names = Object.keys(questions);
        const tooBig =
          (control.max_questions && names.length > control.max_questions) ||
          (control.max_body && body.length > control.max_body);
        if (tooBig) {
          return send(res, 400, { detail: { error_type: "max_tokens_exceeded" } });
        }
        stats.questions += names.length;
        stats.batches.push(names.length);
        const out = {};
        for (const name of names) out[name] = answerFor(questions[name]);
        send(res, 200, {
          model: parsed.model || "jev-latest",
          answers: out,
          usage: {
            input_tokens: control.count_tokens ? countTokens(body) : 0,
            output_tokens: 0,
          },
        });
      };
      control.delay_ms > 0 ? setTimeout(finish, control.delay_ms) : finish();
    });
  })
  .listen(Number(process.env.PORT || 4372), "127.0.0.1");
