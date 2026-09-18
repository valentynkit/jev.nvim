# The demo

One take, two assets. `make demo` renders both from the same PNG frames:

| file | size | where |
|---|---|---|
| `demo.gif` | 960 wide, ~900 KB | README, r/neovim, Dotfyle |
| `demo.mp4` | 1080x1080, ~1 MB | X |

```sh
make demo                          # vhs demo.tape, then both scripts below
./scripts/gif.sh .demo-frames demo.gif 50 960
./scripts/mp4.sh .demo-frames demo.mp4 50
```

No key and no network: `demo.tape` starts `tests/fake_jev.js` in a hidden block and points
`JEV_BASE_URL` at it, so the demo renders from a clean clone. It also clones
`kanagawa.nvim` into `.tests/site/` the first time `demo/init.lua` loads.

## What is staged, and what is not

The clip is a real run of the plugin against the real corpus. Three things are set for the
camera and nowhere else, and all three are in `demo.tape`:

- `FAKE_JEV_DELAY_MS=600`. The fake answers instantly, so without this the whole list
  lands in one frame and there is nothing to watch.
- `concurrency = 1`. The default is 4; at 4 the batches arrive in pairs and the progress
  bar jumps. One at a time reads better.
- `width = 6`. Questions per request, so 48 functions become 8 visible batches instead of
  the 1 the token budget would pack them into.

Everything else is stock. The colorscheme is Kanagawa Wave and the chrome is off
(`demo/init.lua`), which is configuration any user has. Nothing in `demo/` changes how the
plugin behaves, so the clip shows what a `lazy.nvim` install gives you.

**The numbers in the clip come from the fake.** `$0.0005`, `p50 622ms` and every
probability are `fixtures/answers.json`, not measured. Do not post this take. `make record`
then re-render: the tape is backend-agnostic, so pointing `JEV_BASE_URL` at the gateway
shim instead of the fake produces the identical clip with real answers.

## The frame

1200x880, `FontSize 24`, which is 80 columns by 28 rows. 80 is the floor: `errors.py:14`
is 79 characters and the shot is worthless if it truncates. The MP4 scales that to 1080
wide and sits it between two 144px bars carrying the one line of context and the handle,
because X autoplays muted in a feed where the post text may not be read.

Colours are Kanagawa Wave, inlined into `Set Theme` in the tape rather than read from
`~/.dotfiles/themes/kanagawa-wave/colors.toml`. It has to render the same on a machine
with no dotfiles.

## The beats

| t | what |
|---|---|
| 0.0 | `rg -n --no-heading 'except\|catch\|rescue\|pcall\|err != nil' *` |
| 2.0 | 15 matches. None in Rust. Five of them are `connect_pool`, which handles its error. |
| 4.5 | `nvim errors.py` |
| 6.5 | `:Jev swallows an exception without logging or rethrowing it *` |
| 8.0 | panel top right, quickfix grows in waves, `0.94` lands on `save_event` |
| 11 | `:cnext` mid-fill: the list keeps growing and the cursor holds |
| 14 | `:JevSort`, then `:cc 2` |
| 17 | panel collapses to the done line, then closes: probability, the bug, the ranked list |

The last frame is the still for the second post in the thread.

## Known rough edges

- `ffmpeg` here has no libfreetype, so the two caption lines are baked into a plate by
  ImageMagick and overlaid, rather than drawn by `drawtext`. See `scripts/mp4.sh`.
- `vhs` 0.12 cannot encode against ffmpeg 9, so `scripts/gif.sh` runs the
  palettegen/paletteuse pipeline itself from the frame dump. See `scripts/gif.sh`.
