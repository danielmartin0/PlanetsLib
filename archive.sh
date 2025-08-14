#!/bin/bash

dir=$(dirname "$scriptpath")
cd "$dir" || exit


git archive --prefix=PlanetsLib_1.10.7/ -o PlanetsLib_1.10.7.zip HEAD
