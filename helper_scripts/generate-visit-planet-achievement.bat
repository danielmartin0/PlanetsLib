@echo off
if [%1] == [] (
    echo No input file provided.
    echo Usage: %0 image [output] & exit /b 1
)

set output=%2
if [%2] == [] set output=output.png

@REM Create a mask around the size of the frame
magick -size 128x128 xc:Black -fill White -draw "circle 64,64 64,114" -alpha Copy achievement-frame-mask.png

@REM 1. Take background image
@REM 2. Resize the input image
@REM 3. Layer the resized image onto the background in the correct spot, using a mask
@REM 4. Layer the overlay on top
magick visit-planet-background.png ^( ^
        ^( %1 -resize "116x116^" -crop "116x116!" -delete 1 ^) ^
    -geometry "+25+33" achievement-frame-mask.png ^) -compose src-over -composite ^
    visit-planet-overlay.png -compose src-over -composite ^
    %output%