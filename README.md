## pqr

Runs package.json scripts without Node and npm overhead.

```shellsession
$ time npm run echo test

> @ echo pqr/test
> echo "test"

test

real    0m0.200s
user    0m0.186s
sys     0m0.017s

$ time pqr echo test
test

real    0m0.003s
user    0m0.003s
sys     0m0.000s
```


### Installation

```shellsession
$ go get github.com/charmander/pqr
```


### Intended incompatibilities with `npm run-script`

- pqr runs only the specified script; npm [also runs scripts with `pre` and `post` prefixes][npm-pre-post] if they exist. Use `[pqr prescript && ]pqr script[ && pqr postscript]` for compatibility.

- pqr uses the nearest `package.json` it finds along the current path (`./package.json`, `../package.json`, `../../package.json`, …). npm uses [a prefix consistent across all commands][npm-prefix]: the nearest directory containing either a `package.json` or a `node_modules` after first removing all `node_modules` components from the end of the current path.

- pqr adds arguments to the end of script commands with `"$@"`; npm [double-quotes each argument after escaping only double quotes][npm-quoting]. (For example, `npm run-script script -- '\"; yes #'` will execute `yes`.)

- pqr runs the script with an unmodified environment; npm adds several of its own strings. (See `npm run-script env`.)

- pqr requires `sh`; npm will use [`%ComSpec%` or `cmd` on Windows][npm-windows].

- pqr doesn’t include npm’s `node-gyp-bin` in `PATH` (because it doesn’t require npm to exist); find the directory with `npm run env dirname '$(which node-gyp)'` and run <code>PATH=<i>node-gyp-bin</i>:$PATH pqr …</code> for near-compatibility.


### Bugs

- If package.json doesn’t contain a `scripts` key, pqr will read any key matching `scripts` case-insensitively ([golang/go#14750][go-14750]).


### Running nested scripts with pqr

Create an npm wrapper that delegates to pqr if its first argument is `run-script` or `run`, and the original npm otherwise; add it to your `PATH` before the original npm.


  [npm-pre-post]: https://github.com/npm/npm/blob/d081cc6c8d73f2aa698aab36605377c95e916224/lib/run-script.js#L158
  [npm-prefix]: https://github.com/npm/npm/blob/d081cc6c8d73f2aa698aab36605377c95e916224/lib/config/find-prefix.js
  [npm-quoting]: https://github.com/npm/npm/blob/d081cc6c8d73f2aa698aab36605377c95e916224/lib/run-script.js#L178
  [npm-windows]: https://github.com/npm/npm/blob/d081cc6c8d73f2aa698aab36605377c95e916224/lib/utils/lifecycle.js#L237
  [go-14750]: https://github.com/golang/go/issues/14750
