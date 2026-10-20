#!/bin/bash

dir=$(dirname "$scriptpath")
cd "$dir" || exit


git archive --prefix=PlanetsLib_2.2.1/ -o PlanetsLib_2.2.1.zip HEAD

sh update_documentation.sh