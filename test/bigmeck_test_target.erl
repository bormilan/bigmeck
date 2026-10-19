-module(bigmeck_test_target).

-export([fun_a/0, fun_a/1, echo/1, fail/1]).

-spec fun_a() -> original.
fun_a() ->
    original.

-spec fun_a(term()) -> {original, term()}.
fun_a(Value) ->
    {original, Value}.

-spec echo(term()) -> term().
echo(Value) ->
    Value.

-spec fail(term()) -> no_return().
fail(Reason) ->
    error(Reason).
