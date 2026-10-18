# test-mods

Development test mods for PlanetsLib. Each subfolder is a standalone Factorio mod used to
exercise a PlanetsLib feature while developing it. They are **for development only** and are
excluded from release builds.

## Usage

Point Factorio at these mods alongside PlanetsLib, for example by copying or symlinking each
folder into your mods directory:

```
ln -s "$PWD/test-mods/planetslib-ground-digger-test" ~/.factorio/mods/planetslib-ground-digger-test
```

Then enable the test mod and run Factorio (or a headless `--dump-data` / `--create`) to check
the feature.

## Contents

- `planetslib-ground-digger-test` — exercises `PlanetsLib.enable_ground_diggers()`:
  registers a recipe on `nauvis` in `data.lua`, and a late-registered recipe on `vulcanus`
  (with a blacklist) from `data-final-fixes.lua`.
