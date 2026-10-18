#!/bin/bash

dir=$(dirname "$scriptpath")
cd "$dir" || exit


git archive --prefix=PlanetsLib_2.1.0/ -o PlanetsLib_2.1.0.zip HEAD

sh update_documentation.sh