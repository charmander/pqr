(**p**ackage **q**uick **r**un)

Runs package.json scripts without Node and npm overhead.

> [!NOTE]
> If you have [Deno][] available, `deno task` can do this too.

```shellsession
$ time npm run echo test

> echo
> echo test

test

real    0m0.479s
user    0m0.249s
sys     0m0.076s

$ time pqr echo test
test

real    0m0.007s
user    0m0.001s
sys     0m0.000s
```


## Installation

A prebuilt executable is available for x86-64-v3 Linux on [the Releases page][github-releases]. You can:

- audit the repository at the tagged version, then
    - [reproduce the build](#reproducing-the-build)
    - [verify GitHub’s attestation that GitHub Actions reproduced the build](#confirming-that-github-actions-reproduced-the-build)

- [verify the author’s signature](#verifying-the-authors-signature)

Then install the executable somewhere on your PATH, e.g. as root:

```shell
install -t /usr/local/bin/ ./pqr
sha256sum --tag /usr/local/bin/pqr  # make sure it's still the same
```


## Intended incompatibilities with `npm run-script`

### Notable

- pqr runs only the specified script; npm [also runs scripts with `pre` and `post` prefixes][npm-pre-post] if they exist (as long as `ignore-scripts` is off). Use `[pqr prescript && ]pqr script[ && pqr postscript]` for compatibility.

- pqr doesn’t support [workspaces][npm-workspaces] yet.

- pqr runs the script with an unmodified environment; npm adds several of its own strings. (See `npm run-script env`.)

- pqr requires `sh`; npm will use [`%ComSpec%` or `cmd` on Windows][npm-windows].

- pqr doesn’t include npm’s `node-gyp-bin` in `PATH` (because it doesn’t require npm to exist); find the directory with `dirname "$(npm run -- env which node-gyp)"` and run <code>PATH=<i>node-gyp-bin</i>:$PATH pqr …</code> for near-compatibility.

- npm provides default definitions for:

    - `env` (`env`)
    - `start` when `server.js` exists (`node server.js`)
    - `restart` (`npm stop --if-present && npm start`)

    pqr doesn’t.

### Niche

- pqr rejects `package.json`s with duplicate definitions of the top-level `scripts` key or of individual scripts; npm uses the last definition of any key, like `JSON.parse`.

- pqr uses the nearest `package.json` it finds along the current path (`./package.json`, `../package.json`, `../../package.json`, …). npm uses [a prefix consistent across all commands][npm-prefix]: the nearest directory containing either a `package.json` or a `node_modules` after first removing all `node_modules` components from the end of the current path.

    This can only cause pqr to run a script in a situation where npm would have errored out.

### Historical

- pqr adds arguments to the end of script commands with `"$@"`; [npm double-quoted each argument after escaping only double quotes][npm-quoting] until version 7. (For example, `npm run-script script -- '\"; yes #'` would execute `yes`.)


## Running nested scripts with pqr

Create an npm wrapper that delegates to pqr if its first argument is `run-script` or `run`, and the original npm otherwise; add it to your `PATH` before the original npm.


## Verifying the prebuilt executable

### Reproducing the build

```shell
zig version
```

> 0.14.0

```shell
zig ld.lld --version
```

> LLD 19.1.7 (compatible with GNU linkers)

```shell
zig build -Drelease -Dcpu=x86_64_v3
objcopy --remove-section=.comment zig-out/bin/pqr
sha256sum --tag zig-out/bin/pqr
```

> SHA256 (zig-out/bin/pqr) = *(same as prebuilt pqr)*

### Confirming that GitHub Actions reproduced the build

Verify GitHub’s attestation that the build was reproduced by GitHub Actions:

```shell
gh attestation verify \
    --signer-digest="$(git rev-parse HEAD)" \
    --deny-self-hosted-runners \
    --source-digest="$(git rev-parse HEAD)" \
    --repo=charmander/pqr \
    ./pqr
```

### Verifying the author’s signature

1. Also download SHA256SUMS and SHA256SUMS.sig from the same release

1. Verify the signature against [the author’s signing key][signing-key]:

    ```shell
    ssh-keygen -Y verify \
        -f allowed-signers \
        -n file \
        -I '~@charmander.me' \
        -s SHA256SUMS.sig \
        <SHA256SUMS
    ```

    > Good "file" signature for ~@charmander.me with …

1. Check the comment in SHA256SUMS to ensure that the signed version is what the release page claims it is

1. Check the hash:

    ```shell
    sha256sum -c SHA256SUMS
    ```

    > pqr: OK


[Deno]: https://deno.com/
[github-releases]: https://github.com/charmander/pqr/releases
[npm-pre-post]: https://github.com/npm/npm/blob/d081cc6c8d73f2aa698aab36605377c95e916224/lib/run-script.js#L158
[npm-prefix]: https://github.com/npm/npm/blob/d081cc6c8d73f2aa698aab36605377c95e916224/lib/config/find-prefix.js
[npm-quoting]: https://github.com/npm/cli/blob/1314dc07e8163099c993d5b0ec775bfef3bd80e0/lib/run-script.js#L182
[npm-windows]: https://github.com/npm/npm/blob/d081cc6c8d73f2aa698aab36605377c95e916224/lib/utils/lifecycle.js#L237
[npm-workspaces]: https://docs.npmjs.com/cli/v11/using-npm/workspaces
[signing-key]: https://charmander.me/keys/
