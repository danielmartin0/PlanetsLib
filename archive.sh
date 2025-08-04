#!/bin/bash

dir=$(dirname "$scriptpath")
cd "$dir" || exit


git archive --prefix=PlanetsLib_1.10.3/ -o PlanetsLib_1.10.3.zip HEAD
