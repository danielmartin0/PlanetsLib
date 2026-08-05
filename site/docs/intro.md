---
sidebar_position: 1
slug: /
---

# PlanetsLib

Code and graphics to help modders creating planets, moons and other systems. This library is a community project. Anyone is welcome to open a pull request on Github. For feature requests, please open an issue. For general discussion, use Discord.

Since other mods make use of the 'orbit structure' this mod provides to the solar system, it is recommended to add PlanetsLib compatibility to your planet mod either by defining your planet prototype using PlanetsLib (as in the first image in the mod portal gallery), or by calling PlanetsLib:update in data-updates.lua (second image in the gallery). Besides improving compatibility with PlanetsLib consumers, this means if another mod updates the position of your planet's orbital parent without moving your planet, your planet will be moved too.

We aim to never make any breaking API changes such that the library is safe to use. We sometimes deprecate APIs by removing them from the documentation, but they stay functional.


# Notes for contributors

* In your pull requests, please list your changes in changelog.txt to be included in the next release. Please also update `README.md` to add sections for your new functionality (even with only 'Documentation pending') and add yourself to the contributors list.
* Contributions MUST be tested before a PR is made, ideally with multiple planets installed.
* Feel free to use the file `todo.md`.