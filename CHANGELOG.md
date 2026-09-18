# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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
