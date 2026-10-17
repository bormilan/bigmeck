-module(bigmeck_no_debug_info_target).

-export([fun_a/0]).

-spec fun_a() -> original.
fun_a() ->
    original.
