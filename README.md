# jev.nvim

[![test](https://github.com/valentynkit/jev.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/valentynkit/jev.nvim/actions/workflows/ci.yml)
![Neovim 0.10+](https://img.shields.io/badge/Neovim-0.10%2B-blue)
![MIT](https://img.shields.io/badge/license-MIT-green)

Ask the buffer a question in plain language. Every function in it gets judged, and the
answers land in quickfix ranked by probability.

```vim
:Jev builds a SQL query by string concatenation
```

![demo](demo.gif)

## What the clip shows

It opens on the grep you write when you go looking for SQL injection:

```console
$ rg -n 'SELECT.*\+' fixtures/corpus/
5 matches
```

Five, and every one of them is a `+`. There are twelve. Lua concatenates with `..`, Rust
with `format!`, Python with an f-string, TypeScript with a template literal. One idea,
five syntaxes, and the regex that catches one catches none of the rest. That is not noise,
it is a false negative: you searched, you got five, you stopped.

Then the same question in English, over the same twelve files:

```
errors.rs |14 col 1| 0.98  find_user
errors.ts |14 col 1| 0.97  findUser
errors.py |20 col 1| 0.96  find_user
errors.js |13 col 1| 0.95  findUser
report.rs |15 col 1| 0.95  report_query
errors.go |20 col 1| 0.94  findUser
errors.lua|14 col 1| 0.93  M.find_user
report.py |14 col 1| 0.93  report_query
```

grep is shaped like the language. The question is not.

The clip is rendered against the plugin's test fake so it runs from a clean clone, which
means the probabilities in it are fixtures rather than measurements. `demo/README.md` lists
exactly what is staged for the camera and what is not.

## Why

grep needs the pattern, and half the searches worth running have no pattern. "Where do we
retry without a backoff." "Which handlers touch the database before checking auth." "What
swallows an exception and returns a default." You know the shape of the answer, not the
string.

jev.nvim splits the buffer with treesitter and sends one question per function to
TypeSafe's Jev. Jev is a decision model, not a chat model: it answers a typed question with
a calibrated probability rather than prose, which is what makes a sorted list possible at
all.

Because the answer lands in quickfix, it is already an edit pass: `:cnext`, `:cdo`, your
usual trouble mapping. And because the plugin reads the buffer rather than the file, it
judges the edit you have not saved yet.

The honest limit, up front: it judges each function alone. A question about how two
functions interact gets the wrong list, because nothing in the request knows the other
function exists.

## Install

Neovim 0.10+, `curl`, and a treesitter parser for the language you are asking about (lua,
python, rust, go, javascript, typescript, tsx today).

```lua
-- lazy.nvim
{ "valentynkit/jev.nvim", cmd = { "Jev", "JevSort", "JevClear" }, opts = {} }
```

Then put your key in the environment, however you already do that:

```sh
export TYPESAFE_API_KEY=...
```

| variable | required | purpose |
|---|---|---|
| `TYPESAFE_API_KEY` | yes | your TypeSafe key |
| `JEV_BASE_URL` | no | point at a gateway shim, a recording proxy, or the test fake |
| `JEV_MODEL` | no | defaults to `jev-1.13.0`, pinned because the threshold was measured against one model |
| `JEV_CONCURRENCY` / `JEV_ATTEMPTS` / `JEV_TIMEOUT_MS` | no | request tuning, defaults 4 / 3 / 20000 |

## Use

```vim
:Jev functions that swallow errors
:Jev builds a SQL query by string concatenation lua/**/*.lua
:'<,'>Jev is a test that does not assert anything
:Jev! validates user input before writing src/**/*.ts
```

The second argument is a glob, `vim.fn.glob()` semantics. A visual range narrows the run to
the functions the range overlaps. `:Jev!` skips the confirmation on a wide glob. `--` ends
the question if its last word looks like a path.

While it runs, a panel in the top right shows the question, a progress bar of batches,
functions and requests and how many are in flight, the estimated tokens and cost, elapsed
and p50 per request, and the last three hits. When it finishes, those collapse to one done
line. Every hit at or above the threshold also gets its probability as virtual text at the
end of the function's signature line. `:JevClear` removes both.

```lua
require("jev").setup({
  threshold = 0.75,       -- hits below this are marked "(below t)", never dropped
  confirm_above = 200,    -- functions, above which a glob asks before spending
  concurrency = 4,
  budget = 45000,         -- tokens per request
  panel = true,
  panel_linger_ms = 2000,
  virtual_text = true,
  pre_filter = nil,       -- lua pattern or fun(unit): boolean, run before Jev sees anything
})
```

`pre_filter` is the cost knob and the regex belt: `pre_filter = "pcall"` sends only the
functions that already mention `pcall`.

## What it costs

Input is $0.042 per million tokens and output is free. The 48 functions of the fixture
corpus estimate to about 13,000 tokens, which is one request and **$0.0005**, and the
plugin prints that figure before it sends anything:

```
jev: 48 functions, 1 request, about $0.0005
```

Above `confirm_above` it asks first. That number is arithmetic over the estimator's own
token count, not a measurement, so it holds whatever endpoint you point at.

## How it works

1. `vim.treesitter.query.get(lang, "jev")` over the buffer text, or over each glob file
   read with `readfile`. Never a second buffer.
2. Each function becomes a payload of file, name, signature, doc and source, trimmed to
   3,450 characters.
3. A session cache keyed on sha256 of the question and the unit source drops everything
   unchanged since the last run, so re-asking an edited buffer pays only for what changed.
4. The rest is packed greedily under 45,000 estimated tokens per request, state shipped
   once and one question per function, four requests in flight.
5. Responses land through `vim.schedule` and append to quickfix in arrival order, so
   `:cnext` is safe from the first batch. One sort at the end, and only if you have not
   moved yet; otherwise it tells you about `:JevSort`.
6. A request rejected as over budget is bisected and both halves requeued. A single unit
   too big for one request halves its source once, then gives up rather than looping.

Code owns counting, sorting, thresholds, byte ranges, the token estimate, cost arithmetic
and retries. Jev only answers the one question per function. Every error path fails open:
no key, no `curl`, no parser, a timeout or a 500 gets one message and leaves you where you
were.

## Accuracy

Not measured yet, and the table below is blank on purpose rather than filled with a guess.

| | |
|---|---|
| precision | `__` at t=`__` |
| held out | n=`__` of `__` |
| 95% CI | `__` to `__` |

`make measure` runs the three corpus questions over `fixtures/corpus`, sweeps thresholds on
a tuning half, and reports precision on a held-out half the selection never saw. Both
tables print, labelled. Splitting by file means two functions from one module cannot
straddle the split, and alternating inside each language keeps all six languages in both
halves.

Filling it needs one paid run against a real endpoint: `make record` once, then `make
measure` as often as you like, because recordings replay for free. Until that happens,
`opts.threshold` is a starting point rather than a result.

## Limits

- One function at a time. A question about how two functions interact returns the wrong
  list.
- Negated questions read badly, and `noul(X) + noul(not X)` is not guaranteed to be 1.
  Phrase positively: "swallows an exception", not "does not handle errors".
- Seven languages. Anything else gets one message and no request.
- Rust and Go have no exceptions, so a question phrased around exceptions asks those
  languages something slightly different from what it asks Python. The corpus records that
  as a number rather than hiding it.
- The corpus is ours, not yours. The threshold that holds on 48 functions of fixture code
  is a starting point; re-run the sweep on your own labels before trusting it.
- Answers arrive in batch order, not in ranked order, until the final sort.
- No disk cache. Restarting Neovim forgets everything.

## Development

```sh
make test     # starts the fake Jev, runs the suite headless, no network, no key
make dump     # one line per extracted function across the corpus
make measure  # replays fixtures/recorded, prints the headline, writes measure.json
make record   # one-time, costs money: records real answers into fixtures/recorded
make demo     # renders demo.gif and demo.mp4 from demo.tape
```

The first `make test` clones plenary and nvim-treesitter into `.tests/` and compiles the
seven parsers. It never touches your own Neovim config: every XDG path is redirected inside
`.tests/`. `.env.example` lists the variables the record and measure steps read.

Design notes are in [docs/design.md](docs/design.md), contribution rules in
[CONTRIBUTING.md](CONTRIBUTING.md), and `:help jev` is [doc/jev.txt](doc/jev.txt).

## License

MIT. The treesitter patterns under `queries/` are Apache 2.0, see [NOTICE](NOTICE).
