#!/bin/bash

dir=$(dirname "$scriptpath")
cd "$dir" || exit


git archive --prefix=PlanetsLib_1.12.1/ -o PlanetsLib_1.12.1.zip HEAD
