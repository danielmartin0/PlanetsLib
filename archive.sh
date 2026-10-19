#!/bin/bash

dir=$(dirname "$scriptpath")
cd "$dir" || exit


git archive --prefix=PlanetsLib_2.1.1/ -o PlanetsLib_2.1.1.zip HEAD

sh update_documentation.sh