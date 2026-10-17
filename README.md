# BIGMeck — Behaviourally Isolated Global Meck

Request-scoped mocking for Erlang, built on [Meck](https://github.com/eproxus/meck).

BIGMeck is a thin wrapper that selects mocked return values using the calling
process's `x-request-id`. Calls carrying a matching ID receive the configured
value; other calls use the original function.

**Status:** early development. The repository contains the library skeleton,
Meck dependency, development tools, and basic Meck tests. The BIGMeck API below
is planned and is not implemented yet.

## How it works

- `bigmeck:new/0` starts one owner process with one shared ETS table.
- `bigmeck:expect(Module, Function, Arity, ReturnValue)` reads the registering
  process's request ID and stores a literal return value under
  `{RequestId, Module, Function, Arity}`. It installs a shared Meck callback for
  the target function; later registrations update ETS.
- When that function is called, the callback reads the calling process's ID and
  looks up its return value. An unmatched call passes through with its original
  arguments. The callback runs in the caller, independently of the ETS owner.
- `bigmeck:unload/0` stops the owner and destroys the table. The caller invokes
  it after the test run and manages Meck module setup and teardown separately.

Repeating `expect/4` for the same key replaces its value. Expectations persist
until replaced or the table is destroyed, so unrelated test cases should use
distinct request IDs. Processes sharing an ID share its expectations.

## Intended usage

This example illustrates the planned API; it is not runnable yet.

```erlang
%% Shared setup: keep the Meck creator alive for the test run.
bigmeck:new().
ok = meck:new(my_service, [passthrough]).

%% Assume my_service:fun_a/0 normally returns original_value.
put('x-request-id', <<"request-a">>).
ok = bigmeck:expect(my_service, fun_a, 0, mocked_value).
mocked_value = my_service:fun_a().

%% Another request uses the original function.
put('x-request-id', <<"request-b">>).
original_value = my_service:fun_a().

%% Calls without an ID also use the original function.
erase('x-request-id').
original_value = my_service:fun_a().

%% Caller-managed teardown after the test run.
ok = meck:unload(my_service).
ok = bigmeck:unload().
```

`expect/4` returns `ok` on success and raises errors for a missing/non-binary
request ID, invalid target, or module not initialized with Meck. Missing ETS
storage also raises an error, including in installed callbacks. An unexpected
owner exit loses the table; the caller can monitor the owner to fail its test
fixture. There is no automatic recovery in the first version.

Use Meck directly for module setup, unloading, history, and validation. Its mock
processes are linked to their creator by default; callers using `no_link` manage
their teardown explicitly. History and validation remain shared across requests.
Expectation changes for a BIGMeck-managed function should go through BIGMeck,
since direct `meck:expect` or `meck:delete` calls can replace its lookup callback.

## Request context

BIGMeck targets applications that already store a binary ID under the atom
`'x-request-id'` in the process dictionary. Set it both when registering an
expectation and in each process making calls that should use it. Your application
handles HTTP headers and propagates IDs to spawned workers.

Meck still replaces modules across the Erlang VM. Its
[usual limitations](https://github.com/eproxus/meck#caveats), including unqualified
calls within a module bypassing expectations, still apply.

## Requirements and development

- Erlang/OTP 28
- rebar3 3.25.1 or newer (CI uses 3.27.0)
- Target modules compiled with `debug_info` and their abstract code retained,
  as required by Meck's passthrough mode.

```sh
rebar3 fmt          # Format Erlang source and configuration
rebar3 fmt --check  # Check formatting without changing files
rebar3 compile      # Compile; warnings fail the build
rebar3 eunit        # Run EUnit tests
rebar3 lint         # Run rebar3_lint
rebar3 check        # Run all checks above without changing files
```

CI runs formatting, compilation, EUnit, and lint on Ubuntu, Windows, and macOS.
See the [development roadmap](docs/roadmap.md) for the implementation plan.
