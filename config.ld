project = 'PlanetsLib (Work in progress)'
description = 'PlanetsLib'
full_description = 'Code, graphics and conventions to help modders creating planets, moons and other systems. This library is a community project and will grow over time. Anyone is welcome to open a [pull request](https://github.com/danielmartin0/PlanetsLib/pulls) on Github. For feature requests, please open an [issue](https://github.com/danielmartin0/PlanetsLib/issues). For general discussion, use [Discord](https://discord.gg/VuVhYUBbWE).'
title = 'PlanetsLib documentation'
dir = 'docs'
template = true
use_markdown_titles = true
readme = "README.md" 
style = 'docs_templates'
template = "docs_templates"
format = 'markdown'
sort_modules=true
ignore=true
file = '.'
kind_names={topic='Manual',module='Libraries'}
tparam_alias('array','array')
tparam_alias('array2d','array')
tparam_alias('TechnologyPrototype','[TechnologyPrototype](https://lua-api.factorio.com/latest/prototypes/TechnologyPrototype.html)')
alias("LuaForce",'@{LuaForce}')
alias('ret',{'return',modifiers={type="$1"}})
