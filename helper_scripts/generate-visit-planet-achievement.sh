#!/bin/bash

# Exit immediately if any command fails
set -e

# Check for input argument
if [ -z "$1" ]; then
    echo "No input file provided."
    echo "Usage: $0 image [output]"
    exit 1
fi

# Output file name
output="$2"
if [ -z "$output" ]; then
    output="output.png"
fi

# Create a circular mask the size of the frame
convert -size 128x128 xc:Black -fill White -draw "circle 64,64 64,114" -alpha Copy achievement-frame-mask.png

# Build the final image:
# 1. Background
# 2. Input image resized/cropped
# 3. Apply circular mask
# 4. Add overlay
convert visit-planet-background.png \
    \( \
        \( "$1" -resize "116x116^" -gravity center -crop "116x116+0+0" \) \
        -geometry +25+33 achievement-frame-mask.png \
    \) -compose src-over -composite \
    visit-planet-overlay.png -compose src-over -composite \
    "$output"


rm -f achievement-frame-mask.png