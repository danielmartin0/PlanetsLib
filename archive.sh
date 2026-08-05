#!/bin/bash

dir=$(dirname "$scriptpath")
cd "$dir" || exit


git archive --prefix=PlanetsLib_1.23.5/ -o PlanetsLib_1.23.5.zip HEAD
