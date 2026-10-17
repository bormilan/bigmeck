# BIGMeck development roadmap

Build **Behaviourally Isolated Global Meck** as a thin wrapper around Meck.
Keep the first implementation in `bigmeck.erl`, with one shared ETS owner and
literal return values selected by binary request IDs under `'x-request-id'`.

Milestone [0.0.1](https://github.com/bormilan/bigmeck/milestone/1) has two
implementation tasks. Start each with a small failing test, implement the minimum
behavior, and refactor. Keep tests focused and run `rebar3 check` on OTP 28.

## 1. Meck integration

- [x] Add Meck as a runtime dependency and lock its version.
- [x] Add basic EUnit coverage for expectations, passthrough, unloading, and
      passthrough's requirement for retained target-module debug information.
- [x] Configure erlfmt, compilation with warnings as errors, EUnit, and lint.
- [x] Configure CI for Ubuntu, Windows, and macOS on OTP 28.

## 2. Shared storage lifecycle — issue #6

Tracked in [#6](https://github.com/bormilan/bigmeck/issues/6).

- [ ] Write a failing lifecycle test, then implement `bigmeck:new/0` to start one
      owner and one ETS table, returning only when storage is ready.
- [ ] Keep the owner independent of individual test processes. Make its PID
      available for caller monitoring and document repeated-start behavior.
- [ ] Implement `bigmeck:unload/0` to stop the owner and await table removal;
      already-stopped calls are harmless, and fresh startup has empty storage.
- [ ] Document caller-managed setup and teardown after the test run. Keep Meck
      module management separate; BIGMeck does not track suite completion.

## 3. Request-scoped expectations — issue #1

Tracked in [#1](https://github.com/bormilan/bigmeck/issues/1), after #6.

- [ ] Start with a failing isolation test: request A receives its value while B
      and a caller without an ID use the original function.
- [ ] Implement `expect/4` with entries keyed by request ID and module/function/
      arity, plus a generic Meck callback that reads the caller's ID and ETS.
      Require caller-created Meck mocks and confirm callback installation before
      publishing the first value.
- [ ] Support concurrent registration, multiple targets, literal return values,
      and replacement of an existing value. Retain values until shared teardown.
- [ ] Validate registrations and preserve original arguments and exceptions
      during passthrough. Missing storage raises an explicit error; cover owner
      failure with a small test.
- [ ] Update the README with tested examples and the final API return values.

## 4. First release

- [ ] Confirm formatting, compilation, EUnit, and lint pass on all three CI
      platforms with OTP 28.
- [ ] Review the documented request-ID propagation and Meck requirements.
- [ ] Choose a license and prepare package metadata and release notes.

Per-request cleanup, suite coordination, automatic recovery, argument matchers,
callbacks as return specifications, and sequences are outside the first version.
