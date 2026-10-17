-module(bigmeck_test_target).

-export([fun_a/0, echo/1]).

-spec fun_a() -> original.
fun_a() ->
    original.

-spec echo(term()) -> term().
echo(Value) ->
    Value.
