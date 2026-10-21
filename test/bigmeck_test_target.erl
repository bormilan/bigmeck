-module(bigmeck_test_target).

-export([fun_a/0, fun_a/1, echo/1, fail/1]).

-spec fun_a() -> Return when
    Return :: original.
fun_a() ->
    original.

-spec fun_a(Value) -> Return when
    Value :: term(),
    Return :: {original, term()}.
fun_a(Value) ->
    {original, Value}.

-spec echo(Value) -> Return when
    Value :: term(),
    Return :: term().
echo(Value) ->
    Value.

-spec fail(Reason) -> Return when
    Reason :: term(),
    Return :: no_return().
fail(Reason) ->
    error(Reason).
