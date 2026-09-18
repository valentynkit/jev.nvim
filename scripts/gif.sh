#!/bin/sh
# Assembles a GIF from the PNG frames vhs writes.
#
# ponytail: vhs 0.12 cannot encode against ffmpeg 9 on this machine (its own encode step
# runs and leaves no file), so `make demo` falls back to this. Ceiling: it duplicates
# vhs's palettegen/paletteuse pipeline. Delete it once vhs ships an ffmpeg 9 fix.
set -e
frames=${1:-.demo-frames}
out=${2:-demo.gif}
fps=${3:-50}
width=${4:-960}

ffmpeg -y -loglevel error \
  -framerate "$fps" -start_number 1 -i "$frames/frame-text-%05d.png" \
  -framerate "$fps" -start_number 1 -i "$frames/frame-cursor-%05d.png" \
  -filter_complex "[0][1]overlay,fps=25,scale=$width:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
  -loop 0 "$out"

if command -v gifsicle >/dev/null 2>&1; then
  gifsicle -O3 "$out" -o "$out.opt" && mv "$out.opt" "$out"
fi
du -h "$out"
