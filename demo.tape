# Renders demo.gif. Run from the repo root: vhs demo.tape
# The fake Jev from tests/ answers, so this records without a key and without the network.
# A 500 ms delay is injected so the panel and the quickfix list fill on camera instead of
# arriving in one frame.
Output demo.gif
Output .demo-frames/

Set Shell "zsh"
Set FontSize 18
Set Width 1280
Set Height 760
Set TypingSpeed 45ms
Set Padding 12

Hide
Type "PORT=4372 FAKE_JEV_DELAY_MS=600 node tests/fake_jev.js >/dev/null 2>&1 &"
Enter
Type "export JEV_BASE_URL=http://127.0.0.1:4372"
Enter
Sleep 1s
Type "clear"
Enter
Type "nvim -u tests/minimal.lua fixtures/corpus/errors.py"
Enter
Sleep 4s
Type ":lua require('jev').setup({ width = 6, concurrency = 1, panel_linger_ms = 9000 })"
Enter
Sleep 800ms
Show

Sleep 1200ms
Type ":Jev swallows an exception without logging or rethrowing it fixtures/corpus/*"
Sleep 700ms
Enter

# The panel fills, quickfix grows in waves, and the probability lands on the signature
# line of the one hit in this buffer.
Sleep 1600ms

# Mid-stream on purpose: the list keeps growing under the cursor and the cursor holds.
Type ":cnext"
Enter
Sleep 4000ms

Type ":JevSort"
Enter
Sleep 1800ms

# Land on the second entry: the probability is sitting on its signature line.
Type ":cc 2"
Enter
Sleep 3000ms

Hide
Type ":qa!"
Enter
Type "kill %1"
Enter
