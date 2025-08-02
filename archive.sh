#!/bin/bash

dir=$(dirname "$scriptpath")
cd "$dir" || exit


git archive --prefix=PlanetsLib_1.9.0/ -o PlanetsLib_1.9.0.zip HEAD
