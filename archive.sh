#!/bin/bash

dir=$(dirname "$scriptpath")
cd "$dir" || exit


git archive --prefix=PlanetsLib_2.0.10/ -o PlanetsLib_2.0.10.zip HEAD

sh update_documentation.sh