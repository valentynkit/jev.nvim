#!/bin/sh
# Square MP4 for X, from the same PNG frames vhs writes for the GIF.
#
# X autoplays muted in a scrolling feed, so the clip carries its own one line of context
# and its own handle. The 1200x880 terminal scales to 1080 wide and sits between two
# Kanagawa-background bars, which is where those two lines go.
#
# ponytail: the bars are baked by ImageMagick because this ffmpeg has no libfreetype, so
# the drawtext filter does not exist. Ceiling: two tools where one would do. Collapse it
# into a single ffmpeg drawtext call if a freetype build ever lands.
set -e
frames=${1:-.demo-frames}
out=${2:-demo.mp4}
fps=${3:-50}

font=/System/Library/Fonts/SFNSMono.ttf
[ -f "$HOME/Library/Fonts/JetBrainsMonoNerdFont-Bold.ttf" ] &&
  font="$HOME/Library/Fonts/JetBrainsMonoNerdFont-Bold.ttf"

# .png in the name so both magick and ffmpeg infer the format from it.
plate=$(mktemp -t jevplate).png
magick -size 1080x1080 xc:'#1f1f28' \
  -font "$font" \
  -pointsize 34 -fill '#dcd7ba' -gravity North \
  -annotate +0+50 "grep needs a pattern. The question doesn't." \
  -pointsize 26 -fill '#727169' -gravity South \
  -annotate +0+56 'jev.nvim    github.com/valentynkit/jev.nvim' \
  "$plate"

ffmpeg -y -loglevel error \
  -loop 1 -i "$plate" \
  -framerate "$fps" -start_number 1 -i "$frames/frame-text-%05d.png" \
  -framerate "$fps" -start_number 1 -i "$frames/frame-cursor-%05d.png" \
  -filter_complex "[1][2]overlay,fps=30,scale=1080:-2[v];[0][v]overlay=0:144:shortest=1,format=yuv420p" \
  -c:v libx264 -preset slow -crf 18 -movflags +faststart "$out"

rm -f "$plate"
du -h "$out"
