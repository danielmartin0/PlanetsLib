#!/bin/bash

dir=$(dirname "$scriptpath")
cd "$dir" || exit


git archive --prefix=PlanetsLib_1.13.7/ -o PlanetsLib_1.13.7.zip HEAD
