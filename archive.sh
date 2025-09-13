#!/bin/bash

dir=$(dirname "$scriptpath")
cd "$dir" || exit


git archive --prefix=PlanetsLib_1.13.0/ -o PlanetsLib_1.13.0.zip HEAD
