# Contributing

Everything runs offline. `make test` starts the fake Jev, compiles the parsers into
`.tests/` on first run, and never touches your own Neovim config or the network beyond the
two git clones it needs.

```sh
make test     # the suite
make dump     # one line per extracted function across the corpus
make measure  # replays fixtures/recorded, prints the headline, writes measure.json
```

## The fake and the proxy

`tests/fake_jev.js` (port 4372) answers a request by looking each unit up in
`fixtures/answers.json` by `<basename>:<name>`. Anything it does not know comes back at
0.02. It also serves `/_stats`, `/_reset` and `/_control`, which the specs use to make it
return a 429 once, a 400 that says `max_tokens_exceeded`, or a slow answer.
`FAKE_JEV_COUNT_TOKENS=1`
makes it echo a real `usage.input_tokens` counted off the received body, which is what the
estimator is calibrated against.

`tools/proxy.js` (port 4373) is record and replay. It hashes `sha256(state + questions)`
and serves `fixtures/recorded/<hash>.json` when that file exists. With `JEV_UPSTREAM` set
it forwards a miss upstream and writes the answer; with `JEV_UPSTREAM` empty it never
leaves the machine, which is what `make measure` uses. Recording costs money and is a
one-time thing: `make record`, commit `fixtures/recorded/`, everything after that is free.

## Adding a language

Four files, no code.

1. `queries/<lang>/jev.scm`. Copy the `@function.outer` patterns from
   nvim-treesitter-textobjects `queries/<lang>/textobjects.scm` and rename the capture to
   `@function.outer` inside our own `jev` group. Record what you changed in `NOTICE`; those
   patterns are Apache 2.0 and ours is MIT.
2. `lua/jev/extract.lua`: add the filetype to `by_filetype` and the extension to
   `by_extension`, and the language to `M.languages`.
3. `fixtures/corpus/errors.<ext>` and `fixtures/corpus/report.<ext>`, four functions each.
   One true positive per question per file, plus one tempting negative that shares the
   keywords and not the behaviour. Keep them under a few KB.
4. `fixtures/labels.json` and `fixtures/answers.json`: one entry per function per question,
   keyed `<basename>:<name>`. Labels are the ground truth, answers are what the fake
   returns. `make dump` prints the exact names the extractor produced, so paste from there
   rather than typing them.

Then add the language to `tests/minimal.lua`'s parser list and run `make test`. The split
in `lua/jev/score.lua` alternates inside each language, so an even number of corpus files
per language keeps both halves balanced.

## Rules the code follows

- Never block the UI. Every callback that touches vim state goes through `vim.schedule`.
- Jev only ranks. Code owns counting, sorting, thresholds, byte ranges, the token estimate,
  cost arithmetic and retries.
- Every error path fails open with one message, never a stack trace.
- Hits below the threshold are marked `(below t)`, never dropped.
- Numbers in the README come from `make measure` or stay `__`.

## Pull requests

Specs first, and say which `make` target you ran. New behaviour needs a spec that fails
without it. Deliberate shortcuts get a `ponytail:` comment naming the ceiling and the
upgrade path.
