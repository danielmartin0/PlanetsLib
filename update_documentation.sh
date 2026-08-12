#!/bin/bash

dir=$(dirname "$scriptpath")
cd docs-source
npm run docusaurus build && rm -rf ../docs && mv build ../docs
echo "planetslib.foundrygg.com" > ../docs/CNAME