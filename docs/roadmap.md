# BIGMeck development roadmap

The first request-scoped implementation is present, with ten focused BIGMeck
tests alongside the three existing Meck tests. Release checks are tracked below.

Keep development to one implementation task in milestone
[0.0.1](https://github.com/bormilan/bigmeck/milestone/1), with the implementation in
`bigmeck.erl`. Start with one small failing test and add focused cases only as the
behavior needs them.

## Agreed behavior

- `bigmeck:expect(Module, Function, Arity, ReturnValue)` reads the registering
  process's binary ID under the atom `'x-request-id'`, ensures the shared ETS
  table exists, and stores the literal return under
  `{RequestId, Module, Function, Arity}`. It returns `ok` on success.
- The first expectation starts a plain process that creates and owns the table.
  All modules, functions, and requests reuse that one owner and table. The owner
  only keeps ETS alive; reads and writes happen directly in calling processes.
  There is no `bigmeck:new` API or `gen_server`.
- Use Meck's normal setup and options through `meck:new/2` when needed. Callback
  installation uses `meck:expect`, preserving its implicit passthrough setup for
  a module that has not been initialized explicitly.
- A shared Meck callback reads the calling process's request ID and looks up its
  return value directly in ETS. Unmatched or unusable IDs pass through with the
  original arguments and exceptions.
- Repeating an expectation replaces that key's value. Entries remain until
  replaced or the owner exits. Unrelated test cases use distinct IDs.
- The table stores only expected returns. There is no module registry or
  callback-marker storage, and BIGMeck does not automatically unload Meck modules.
- After the run, `bigmeck:unload/0` only stops the owner and ETS destroys its
  table. The library does not track suites, drain calls, or perform per-request
  cleanup.
- Unexpected owner loss is a fixture failure. An installed callback raises an
  explicit error if storage is missing. There is no background restart or
  recovery of lost expectations; lazy initialization creates an empty table.
- Registration errors raise exceptions. Prefer Meck's existing errors where
  applicable.
- The first version supports arities 0–20, as agreed, using `erl_eval` to create
  callbacks without generating additional modules.

## 1. Existing foundation

- [x] Meck dependency and lockfile.
- [x] Basic tests for Meck setup, expectations, passthrough, unloading, and retained
      target-module debug information.
- [x] Formatting, compilation with warnings as errors, EUnit, and lint.
- [x] CI matrix for Ubuntu, Windows, and macOS on OTP 28.
- [x] Add a Dialyzer check to the CI matrix.
- [x] Require 100% line coverage in CI, including tests for owner startup races,
      failure, and timeouts.

## 2. Request-scoped expectations and shared storage — issue #1

Tracked in [#1](https://github.com/bormilan/bigmeck/issues/1). Storage setup,
request-scoped dispatch, and stopping the owner belong to this single task.

- [x] First, write and run a failing isolation test: request A gets its value
      while B and a caller without an ID get the original result. No separate
      BIGMeck setup call is needed.
- [x] Implement lazy shared ETS startup inside `expect/4`. One plain owner
      creates the table; callers wait until it is ready and reuse it across all
      targets. Keep the table alive independently of individual test processes.
- [x] Store request-specific literal returns and install a shared Meck callback
      for each function/arity. Use direct ETS lookup, replacement, and passthrough
      without metadata entries in ETS.
- [x] Preserve Meck's normal setup behavior and keep concurrent registrations
      safe. Use the agreed 0–20 argument callback builder.
- [x] Add the stop-only `unload/0` helper. Owner exit automatically destroys ETS.
- [x] Add focused cases as needed for replacement, target separation, arguments,
      concurrency, validation, storage lifetime, and table removal. Keep tests
      small and original function exceptions intact.

## First release

- [x] Run `rebar3 check` locally on OTP 28.
- [ ] Verify CI on Ubuntu, Windows, and macOS after pushing.
- [x] Replace proposed README examples with tested usage.
- [x] Review request-ID propagation and Meck requirements.
- [ ] Choose a license and prepare package metadata and release notes.
