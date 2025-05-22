## pqr

Runs package.json scripts without Node and npm overhead.

> [!NOTE]
> If you have [Deno][] available, `deno task` can do this too.

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

#### Notable

- pqr runs only the specified script; npm [also runs scripts with `pre` and `post` prefixes][npm-pre-post] if they exist (as long as `ignore-scripts` is off). Use `[pqr prescript && ]pqr script[ && pqr postscript]` for compatibility.

- pqr doesn’t support [workspaces][npm-workspaces] yet.

- pqr runs the script with an unmodified environment; npm adds several of its own strings. (See `npm run-script env`.)

- pqr requires `sh`; npm will use [`%ComSpec%` or `cmd` on Windows][npm-windows].

- pqr doesn’t include npm’s `node-gyp-bin` in `PATH` (because it doesn’t require npm to exist); find the directory with `npm run env dirname '$(which node-gyp)'` and run <code>PATH=<i>node-gyp-bin</i>:$PATH pqr …</code> for near-compatibility.

- npm provides default definitions for:

    - `env` (`env`)
    - `start` when `server.js` exists (`node server.js`)
    - `restart` (`npm stop --if-present && npm start`)

    pqr doesn’t.

#### Niche

- pqr uses the nearest `package.json` it finds along the current path (`./package.json`, `../package.json`, `../../package.json`, …). npm uses [a prefix consistent across all commands][npm-prefix]: the nearest directory containing either a `package.json` or a `node_modules` after first removing all `node_modules` components from the end of the current path.

    This can only cause pqr to run a script in a situation where npm would have errored out.

#### Historical

- pqr adds arguments to the end of script commands with `"$@"`; [npm double-quoted each argument after escaping only double quotes][npm-quoting] until version 7. (For example, `npm run-script script -- '\"; yes #'` would execute `yes`.)


### Running nested scripts with pqr

Create an npm wrapper that delegates to pqr if its first argument is `run-script` or `run`, and the original npm otherwise; add it to your `PATH` before the original npm.


  [Deno]: https://deno.com/
  [npm-pre-post]: https://github.com/npm/npm/blob/d081cc6c8d73f2aa698aab36605377c95e916224/lib/run-script.js#L158
  [npm-prefix]: https://github.com/npm/npm/blob/d081cc6c8d73f2aa698aab36605377c95e916224/lib/config/find-prefix.js
  [npm-quoting]: https://github.com/npm/cli/blob/1314dc07e8163099c993d5b0ec775bfef3bd80e0/lib/run-script.js#L182
  [npm-windows]: https://github.com/npm/npm/blob/d081cc6c8d73f2aa698aab36605377c95e916224/lib/utils/lifecycle.js#L237
  [npm-workspaces]: https://docs.npmjs.com/cli/v11/using-npm/workspaces
