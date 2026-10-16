# bigmeck

An Erlang library targeting Erlang/OTP 28, built with rebar3.

## Requirements

- Erlang/OTP 28
- rebar3 3.25.1 or newer (CI uses 3.27.0)

## Development

```sh
rebar3 compile  # Compile the library; compiler warnings fail the build
rebar3 eunit    # Run EUnit tests
rebar3 lint     # Run rebar3_lint (Elvis)
rebar3 check    # Compile, run EUnit, and lint
```

The first command downloads the development plugin and its dependencies.
The library has no runtime dependencies beyond OTP's `kernel` and `stdlib`.

## Layout

- `src/bigmeck.erl`: starting point for the public API
- `src/bigmeck.app.src`: OTP library application metadata
- `rebar.config`: compiler options, dependencies, and development commands
- `elvis.config`: lint rules for Erlang source files, tests, and project configuration
- `.github/workflows/ci.yml`: GitHub Actions checks on OTP 28

Add library modules under `src/` and EUnit tests under `test/` as functionality is
implemented. The skeleton has no tests yet. As a library application, it does not
need an application callback or supervisor.
