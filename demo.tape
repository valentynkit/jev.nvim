# Renders demo.gif. Run from the repo root: make demo
#
# The fake Jev from tests/ answers, so this records without a key and without the network.
# Two knobs are set for the camera and nowhere else, both disclosed in demo/README.md:
# a 600 ms injected delay, and concurrency 1, so the batches land one at a time instead
# of in a single frame.
#
# Kanagawa Wave, from ~/.dotfiles/themes/kanagawa-wave/colors.toml. Inlined rather than
# read from a theme file on purpose: this has to render the same on a clean clone that
# has no dotfiles.
Output demo.gif
Output .demo-frames/

Set Theme { "name": "Kanagawa Wave", "background": "#1f1f28", "foreground": "#dcd7ba", "cursor": "#dcd7ba", "selection": "#363646", "black": "#16161d", "brightBlack": "#727169", "red": "#c34043", "brightRed": "#e82424", "green": "#76946a", "brightGreen": "#98bb6c", "yellow": "#c0a36e", "brightYellow": "#e6c384", "blue": "#7e9cd8", "brightBlue": "#7fb4ca", "magenta": "#957fb8", "brightMagenta": "#938aa9", "cyan": "#6a9589", "brightCyan": "#7aa89f", "white": "#c8c093", "brightWhite": "#dcd7ba" }

Set Shell "zsh"
Set FontSize 24
Set Width 1200
Set Height 880
Set Padding 20
Set TypingSpeed 30ms

Hide
Type "PORT=4372 FAKE_JEV_DELAY_MS=600 node tests/fake_jev.js >/dev/null 2>&1 &"
Enter
Type "export JEV_BASE_URL=http://127.0.0.1:4372"
Enter
Type "export DEMO_INIT=$PWD/demo/init.lua"
Enter
Type "alias nvim='nvim -u $DEMO_INIT'"
Enter
# Run from inside the corpus so the quickfix paths stay short enough to read.
Type "cd fixtures/corpus"
Enter
Type "PROMPT='%F{4}corpus%f $ '"
Enter
# vhs starts a login shell, so the user's own ripgrep config would otherwise decide how
# the hook frame looks. The clip has to render the same on a machine that has no dotfiles.
Type "unset RIPGREP_CONFIG_PATH"
Enter
Sleep 1s
Type "clear"
Enter
Show

# The hook, and it is a false negative rather than noise. This is the regex you write when
# you go looking for SQL injection, and it finds 5 of the 12 in this corpus: every one
# built with +. It cannot see the Lua .., the Rust format!, the Python f-string or the
# TypeScript template literal, because concatenation has a different shape per language.
Sleep 500ms
Type@22ms "rg -n --no-heading 'SELECT.*\+' *"
Sleep 400ms
Enter
Sleep 2600ms

Type "nvim errors.py"
Enter
Sleep 1600ms

Hide
Type ":lua require('jev').setup({ width = 6, concurrency = 1, panel_linger_ms = 2500 })"
Enter
Sleep 400ms
Type ":20"
Enter
Type "zt"
Show

Sleep 700ms
Type ":Jev builds a SQL query by string concatenation *"
Sleep 600ms
Enter

# The panel fills top right, quickfix grows in waves, and 0.94 lands as virtual text on
# save_event's signature line.
Sleep 2000ms

# Mid-stream on purpose: the list keeps growing under the cursor and the cursor holds.
Type ":cnext"
Enter
Sleep 2600ms

Type ":JevSort"
Enter
Sleep 1400ms

# Land on the Python hit: rust and typescript rank above it, so it is the third entry.
Type ":cc 3"
Enter
Sleep 500ms
# Scroll the concatenated query into frame. It is the reason the number is 0.96.
Type "zt"
# The panel lingers a beat on the done line, then closes itself and leaves the frame the
# post is cropped from: the probability on the signature, the bug under it, the ranked list.
Sleep 4500ms

Hide
Type ":qa!"
Enter
Type "kill %1"
Enter
