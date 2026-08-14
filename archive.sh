#!/bin/bash

dir=$(dirname "$scriptpath")
cd "$dir" || exit


git archive --prefix=PlanetsLib_1.25.1/ -o PlanetsLib_1.25.1.zip HEAD

sh update_documentation.sh