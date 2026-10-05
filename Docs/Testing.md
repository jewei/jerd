# Run tests

Run `./dev test` from the repository root. It runs the unit tests of every
target in `Packages/JerdKit`. To test one target, name it:

```sh
./dev test JerdWeb
```

Default tests need no root access, no network, and no system changes.
Tests that need real runtimes are opt-in. `./dev test --integration` sets the
`JERD_*` variables that select the prepared runtimes.

The complete test guide is written when the rewrite is complete.
