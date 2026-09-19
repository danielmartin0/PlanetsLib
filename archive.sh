#!/bin/bash

dir=$(dirname "$scriptpath")
cd "$dir" || exit


git archive --prefix=PlanetsLib_1.26.4/ -o PlanetsLib_1.26.4.zip HEAD

sh update_documentation.sh