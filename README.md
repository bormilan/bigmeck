# BIGMeck — Behaviourally Isolated Global Meck

Request-scoped mocking for Erlang, built on [Meck](https://github.com/eproxus/meck).

BIGMeck is a thin wrapper that selects mocked return values using the calling
process's `x-request-id`. Calls carrying a matching ID receive the configured
value; other calls use the original function.

**Status:** early development. Request-scoped expectations, reset and delete,
and the stop-only unload helper are implemented. The first version supports
functions with 0–20 arguments, using Erlang's interpreter to construct Meck callbacks.

## How it works

- `bigmeck:expect(Module, Function, Arity, ReturnValue)` reads the registering
  process's request ID and ensures the shared ETS table exists. The first
  expectation starts a plain process that creates and owns the table. All
  modules and functions reuse that owner and table; reads and writes happen
  directly in calling processes. No `bigmeck:new` call is needed.
- It stores a literal return value under `{RequestId, Module, Function, Arity}`
  and installs a shared Meck callback for the target function/arity. Later
  registrations replace or add values in ETS.
- When that function is called, the callback reads the calling process's ID and
  looks up its return value. An unmatched call passes through with its original
  arguments. The callback runs in the caller, independently of the ETS owner.
- `bigmeck:reset/0` deletes all expectations for the current request ID across
  modules, functions, and arities.
- `bigmeck:delete(Module, Function, Arity)` deletes only the current request's
  expectation for that target. Both operations leave other requests, the shared
  ETS owner, and Meck mocks intact. Calls without a remaining entry pass through.
- `bigmeck:unload/0` only stops the plain owner process after the test run.
  ETS automatically destroys its table when that process exits.

Repeating `expect/4` for the same key replaces its value. Expectations persist
until replaced, explicitly deleted or reset, or the table is destroyed. Unrelated
test cases should use distinct request IDs. Processes sharing an ID share its
expectations, including the effects of reset and delete.

## Usage

Assume `my_service:fun_a/0` normally returns `original_value`.

```erlang
%% Shared setup: keep this process alive for the test run.
ok = meck:new(my_service, [passthrough]).

put('x-request-id', <<"request-a">>).
%% The first expectation also initializes shared ETS storage.
ok = bigmeck:expect(my_service, fun_a, 0, mocked_value).
mocked_value = my_service:fun_a().

%% Remove this request's expectation and restore passthrough for this target.
ok = bigmeck:delete(my_service, fun_a, 0).
original_value = my_service:fun_a().

%% Register again, then remove all expectations belonging to this request.
ok = bigmeck:expect(my_service, fun_a, 0, mocked_value).
ok = bigmeck:reset().
original_value = my_service:fun_a().

%% Another request uses the original function.
put('x-request-id', <<"request-b">>).
original_value = my_service:fun_a().

%% Calls without an ID also use the original function.
erase('x-request-id').
original_value = my_service:fun_a().

%% After the test run, stop the owner so ETS discards its table.
ok = bigmeck:unload().
```

`expect/4` returns `ok` on success and raises errors for a missing/non-binary
request ID, invalid target, or a failure from Meck. `reset/0` and `delete/3` also
return `ok` when no matching expectations exist, including before the first
registration; neither operation creates ETS storage or initializes Meck mocks.
An installed callback raises an error if ETS storage is missing.
An unexpected owner exit loses its table;
the fixture should treat that as a failure. There is no background restart or
recovery of lost expectations; lazy initialization creates an empty table.

Use `meck:new/2` for explicit shared setup and custom options. If it is omitted,
BIGMeck preserves `meck:expect`'s implicit passthrough setup. Either way, keep
the process that creates the Meck mock alive while it is in use. For parallel
tests, initialize each shared Meck module once in a fixture before starting
the tests.

The named, public ETS table stores only `{RequestId, Module, Function, Arity}`
keys and literal return values. Parallel tests in the same Erlang VM share it;
the owner outlives the process that first registered an expectation. There is
no module registry, callback-marker storage, or automatic Meck unloading.
Stopping the ETS owner leaves Meck's normal module lifecycle unchanged.
Its mock processes are linked to their
creator by default, so keep the shared setup process alive for the test run.
Use Meck directly for history and validation; these remain shared across requests.
Expectation changes for a BIGMeck-managed function should go through BIGMeck,
since direct `meck:expect` or `meck:delete` calls can replace its lookup callback.

Missing or non-binary IDs in `expect/4`, `reset/0`, and `delete/3` raise
`{invalid_request_id, Value}`. Invalid target arguments to `expect/4` or
`delete/3`, including arities outside 0–20, raise `badarg`. A callback
whose ETS table has been lost raises `bigmeck_storage_unavailable`; an empty
lookup in a live table passes through normally.

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
rebar3 check        # Run formatting, compilation, EUnit, and lint
rebar3 dialyzer     # Check types with Dialyzer
```

Run coverage with the same 100% line-coverage requirement as CI:

```sh
rebar3 eunit --cover
rebar3 as test cover --min_coverage 100 --verbose
```

The HTML report is written to `_build/test/cover/index.html`.

CI runs formatting, compilation, EUnit, lint, Dialyzer, and the 100% coverage
check on Ubuntu, Windows, and macOS.
See the [development roadmap](docs/roadmap.md) for the implementation plan.
