# jev.nvim

Ask the buffer a question, get a quickfix list. `__` functions per request, `__` a query,
`__` ms to first hit, precision `__` (n=`__` of `__` held out, 95% CI `__`).

> The numbers above are unfilled on purpose. They get measured against recorded fixtures
> once a key lands; `make measure` prints them and writes `measure.json`. Nothing here is
> guessed.

```vim
:Jev functions that swallow errors
```

![demo](demo.gif)

## Why

grep needs the pattern, and half the searches worth running have no pattern. "Where do we
retry without a backoff." "Which handlers touch the database before checking auth." "What
swallows an exception and returns a default." You know the shape of the answer, not the
string.

jev.nvim splits the buffer with treesitter, sends one noul per function to TypeSafe's Jev,
and fills quickfix as the batches land. Jev is a decision model, not a chat model: it
answers typed questions with calibrated probabilities in about 100 ms, and input costs
$0.042 per million tokens with output free. A whole buffer is a fraction of a cent.

Because the answer lands in quickfix, it is already an edit pass: `:cnext`, `:cdo`, your
usual trouble mapping. And because the plugin reads the buffer rather than the file, it
judges the edit you have not saved yet.

The honest limit, up front: it judges each function alone. A question about how two
functions interact gets the wrong list, because nothing in the request knows the other
function exists.

## Requirements

Neovim 0.10+, `curl`, and a treesitter parser for the language you are asking about
(lua, python, rust, go, javascript, typescript, tsx today).

## Install

lazy.nvim:

```lua
{ "valentynkit/jev.nvim", cmd = { "Jev", "JevSort", "JevClear" }, opts = {} }
```

```sh
cp .env.example .env
```

| variable | required | purpose |
|---|---|---|
| `TYPESAFE_API_KEY` | yes | your TypeSafe key |
| `JEV_BASE_URL` | no | point at a gateway shim, a recording proxy, or the test fake |
| `JEV_MODEL` | no | defaults to `jev-1.13.0`, pinned because the threshold was measured against it |
| `JEV_CONCURRENCY` / `JEV_ATTEMPTS` / `JEV_TIMEOUT_MS` | no | request tuning, defaults 4 / 3 / 20000 |

## Use

```vim
:Jev functions that swallow errors
:Jev builds a SQL query by string concatenation lua/**/*.lua
:'<,'>Jev is a test that does not assert anything
:Jev! validates user input before writing src/**/*.ts
```

The second argument is a glob, `vim.fn.glob()` semantics. A visual range narrows the run
to the functions the range overlaps. `:Jev!` skips the confirmation on a wide glob.

While it runs, a small panel in the top right shows the question, a progress bar of
batches, functions and requests and how many are in flight, the estimated tokens and cost,
elapsed time and p50 per request, and the last three hits. Every hit at or above the
threshold also gets its probability as virtual text at the end of the function's signature
line. `:JevClear` removes both.

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

## How it works

1. `vim.treesitter.query.get(lang, "jev")` over the buffer text, or over each glob file
   read with `readfile`. Never a second buffer.
2. Each function becomes a payload of file, name, signature, doc and source, trimmed to
   3,450 characters.
3. A session cache keyed on sha256 of the question and the unit source drops everything
   unchanged since the last run, so re-asking an edited buffer pays only for what changed.
4. The rest is packed greedily under 45,000 estimated tokens per request, state shipped
   once and one noul per function, four requests in flight.
5. Responses land through `vim.schedule` and append to quickfix in arrival order, so
   `:cnext` is safe from the first batch. One sort at the end, and only if you have not
   moved yet; otherwise it tells you about `:JevSort`.
6. A request rejected as over budget is bisected and both halves requeued. A single unit
   too big for one request halves its source once, then gives up rather than looping.

Code owns counting, sorting, thresholds, byte ranges, the token estimate, cost arithmetic
and retries. Jev only answers the one question per function.

## Accuracy

`make measure` runs the three corpus questions over `fixtures/corpus`, sweeps thresholds on
a tuning half, and reports precision on a held-out half the selection never saw. Both
tables print, labelled. Splitting by file means two functions from one module cannot
straddle the split, and alternating inside each language keeps all six languages in both
halves.

The table is unfilled until the corpus runs against a real endpoint. Re-run it yourself
with `make record` once, then `make measure` as often as you like: recordings replay for
free.

## Known limits

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
make demo     # renders demo.gif from demo.tape
```

The first `make test` clones plenary and nvim-treesitter into `.tests/` and compiles the
seven parsers. It never touches your own Neovim config: every XDG path is redirected
inside `.tests/`.

## License

MIT. The treesitter patterns under `queries/` are Apache 2.0, see NOTICE.
