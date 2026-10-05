# Run tests

Run `./dev test` from the repository root. It runs the unit tests of every
target in `Packages/JerdKit`. To test one target, name it:

```sh
./dev test JerdWeb
```

Default tests need no root access, no network, and no system changes.
Tests that need real runtimes are opt-in. `./dev test` removes every inherited
`JERD_*` variable. `./dev test --integration web,database,mail,storage` sets
only the switches of the selected groups (for example `JERD_INTEGRATION=1`) and
passes through the runtime path variables of those groups. Set each path to an
absolute path of a trusted local runtime. The variables of each group are in
[Tools](../Tools/README.md#integration-tests).

Without `--verbose`, a test run shows failures with their details, diagnostics,
and the final count. A failed run writes its full output to `.build/logs`.

The complete test guide is written when the rewrite is complete.
