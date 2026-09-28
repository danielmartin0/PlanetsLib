#!/bin/bash

dir=$(dirname "$scriptpath")
cd "$dir" || exit


git archive --prefix=PlanetsLib_2.0.7/ -o PlanetsLib_2.0.7.zip HEAD

sh update_documentation.sh