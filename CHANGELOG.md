# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed

- Inline callbacks are no longer judged as their own functions, and a function bound one
  level below its name (`React.forwardRef`, `React.memo`, an IIFE, a Go `var f = func`)
  now is. Object-literal and class-field functions get their real names.
- Rust attributes, prefixed python docstrings and JSDoc blocks without per-line `*` no
  longer produce wrong or empty documentation for a unit.
- The session cache keys on the doc as well as the source, so editing only the comment
  above a function re-asks it instead of replaying the old answer.
- A second `:Jev` while one is in flight is refused instead of mixing two questions into
  one quickfix list.
- The quickfix list is addressed by id, so a `:grep` or an LSP reference list during a run
  no longer receives the results, or gets replaced by the final sort.
- `--` ends the question: `:Jev is the ratio a.b safe --` no longer globs for `a.b`. A
  range together with a glob is refused.
- Virtual text lands only on the exact file it was judged from, never on an open buffer
  with a similar path.
- The panel fits narrow windows and follows a resize.
- The token estimator charges per character rather than per byte, so non-ASCII source is
  not overcharged and split early.
- `--max-time` honours a short shared deadline, `JEV_CONCURRENCY=0` no longer hangs, and
  an over-budget 400 is recognised by its field rather than by a substring of the body.
- p50 counts only requests that answered; a failed one reported its own retry backoff.
- Neovim 0.10 works, which the documented floor had claimed without ever being run.

### Added

- CI on Neovim 0.10, 0.11, stable and nightly.
- `doc/jev.txt`, so `:help jev` works, and `CONTRIBUTING.md`.

## [0.1.0] - 2026-09-18

### Added

- `:Jev {question}` splits the current buffer into functions with treesitter, sends one
  noul per function, and fills quickfix as batches land. Unsaved edits included.
- `:Jev {question} {glob}` over files on disk, `vim.fn.glob()` semantics, read without
  loading buffers.
- `:'<,'>Jev {question}` narrows the run to the functions a visual range overlaps.
- A live panel in the top right: progress bar, functions and requests and in flight,
  estimated tokens and cost, elapsed and p50, and the last three hits. `opts.panel`.
- Probabilities as virtual text on each hit's signature line, cleared by `:JevClear` and
  by the next run. `opts.virtual_text`.
- Session cache keyed on the question and the unit source, so re-asking an edited buffer
  sends only the functions that changed.
- Greedy packing under a 45,000 token budget, four requests in flight, bisect and requeue
  on a max_tokens_exceeded 400, halve a single oversize unit once before giving up.
- Cost gate: a glob wider than `opts.confirm_above` functions asks first. `:Jev!` skips it.
- `opts.pre_filter`, a Lua pattern or a predicate, run before Jev sees anything.
- Quickfix in arrival order with one final sort, and only while the cursor is still on the
  first entry. `:JevSort` otherwise.
- Vendored treesitter queries for lua, python, rust, go, javascript, typescript and tsx.
- `make measure` prints the headline number and writes measure.json; `make record` records
  real answers once into `fixtures/recorded` and everything replays free after that.
- Fake Jev server, 48-function corpus across six languages, 144 hand-authored labels, and
  the five jaggedness probes from the research as committed numbers.
