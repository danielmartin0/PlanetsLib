#!/bin/bash

dir=$(dirname "$scriptpath")
cd "$dir" || exit


ldoc .
