# P1 patches — provenance and how to apply

Apply BOTH, in this order, to a pristine SillyTavern 1.19.0 `release` tree:

    git apply p1-server-main.diff p1-webpack-serve.diff

## What they do

- `p1-server-main.diff`: replaces the boot-time webpack compile
  (`await webpackMiddleware.runWebpackCompiler({ pruneCache: true })`) with
  `webpackMiddleware.usePrebuiltLib()`.
- `p1-webpack-serve.diff`: removes the boot compile; serves a prebuilt `lib.js`
  resolved and verified through `dist/_webpack/BUILD.json`
  (cacheVersion + bytes + sha256). No content sniffing, no mtime, no guessing.
  Fails loudly instead of serving a junk bundle.

## Verified properties

- `git apply --check` passes on a pristine tree.
- After apply, the file equals the vetted reference (modulo CRLF conversion by git
  autocrlf). A `.gitattributes` is included so the vetted LF form is preserved.
- Selection matrix passes, including the decisive adversarial case:
  manifest `filename` traversal to an existing file whose sha256 matches -> blocked.

## Packaging requirement

The build step `node ./docker/build-lib.js` must run at package time and produce
`dist/_webpack/<hash>/output/lib.js` plus `dist/_webpack/BUILD.json`.

NOTE: `/dist` is listed in `.gitignore`, `.dockerignore` AND `.npmignore`.
The packaging step must un-ignore it, or `usePrebuiltLib()` will (correctly) throw.