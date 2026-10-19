-module(bigmeck_tests).

-include_lib("eunit/include/eunit.hrl").

request_isolation_test() ->
    with_mock(fun() ->
        put('x-request-id', <<"request-a">>),
        ok = bigmeck:expect(bigmeck_test_target, fun_a, 0, mocked),
        ?assertEqual(mocked, bigmeck_test_target:fun_a()),
        put('x-request-id', <<"request-b">>),
        ?assertEqual(original, bigmeck_test_target:fun_a()),
        erase('x-request-id'),
        ?assertEqual(original, bigmeck_test_target:fun_a()),
        put('x-request-id', invalid),
        ?assertEqual(original, bigmeck_test_target:fun_a())
    end).

literal_replacement_and_targets_test() ->
    with_mock(fun() ->
        Other = bigmeck_no_debug_info_target,
        put('x-request-id', <<"request-a">>),
        try
            Literal = fun() -> not_executed end,
            ok = bigmeck:expect(bigmeck_test_target, fun_a, 0, Literal),
            ?assertEqual(Literal, bigmeck_test_target:fun_a()),
            ok = bigmeck:expect(bigmeck_test_target, fun_a, 0, undefined),
            ok = bigmeck:expect(bigmeck_test_target, fun_a, 1, {meck_seq, [literal]}),
            % Meck initializes this second module implicitly.
            ok = bigmeck:expect(Other, fun_a, 0, other_module),
            ?assertEqual(undefined, bigmeck_test_target:fun_a()),
            ?assertEqual({meck_seq, [literal]}, bigmeck_test_target:fun_a(argument)),
            ?assertEqual(other_module, bigmeck_no_debug_info_target:fun_a())
        after
            ok = meck:unload(Other)
        end
    end).

passthrough_arguments_and_errors_test() ->
    with_mock(fun() ->
        put('x-request-id', <<"request-a">>),
        ok = bigmeck:expect(bigmeck_test_target, echo, 1, mocked),
        ok = bigmeck:expect(bigmeck_test_target, fail, 1, suppressed),
        ?assertEqual(mocked, bigmeck_test_target:echo(any_argument)),
        ?assertEqual(suppressed, bigmeck_test_target:fail(badarg)),
        erase('x-request-id'),
        ?assertEqual({original, argument}, bigmeck_test_target:echo({original, argument})),
        ?assertError(badarg, bigmeck_test_target:fail(badarg))
    end).

parallel_registration_and_owner_lifetime_test() ->
    with_mock(fun() ->
        Ids = [integer_to_binary(Index) || Index <- lists:seq(1, 8)],
        Workers = [
            spawn_monitor(fun() ->
                receive
                    go -> ok
                after 2000 ->
                    error(worker_start_timeout)
                end,
                put('x-request-id', Id),
                ok = bigmeck:expect(bigmeck_test_target, fun_a, 0, Id),
                Id = bigmeck_test_target:fun_a()
            end)
         || Id <- Ids
        ],
        lists:foreach(fun({Pid, _Monitor}) -> Pid ! go end, Workers),
        lists:foreach(
            fun({Pid, Monitor}) ->
                receive
                    {'DOWN', Monitor, process, Pid, Reason} -> ?assertEqual(normal, Reason)
                after 2000 ->
                    error(worker_timeout)
                end
            end,
            Workers
        ),
        % All registering processes have exited; their entries remain shared.
        lists:foreach(
            fun(Id) ->
                put('x-request-id', Id),
                ?assertEqual(Id, bigmeck_test_target:fun_a())
            end,
            Ids
        ),
        ?assertEqual(length(Ids), ets:info(bigmeck_expectations, size))
    end).

unload_only_stops_storage_test() ->
    with_mock(fun() ->
        put('x-request-id', <<"request-a">>),
        ok = bigmeck:expect(bigmeck_test_target, fun_a, 0, mocked),
        ok = bigmeck:unload(),
        ?assertEqual(undefined, ets:whereis(bigmeck_expectations)),
        ?assert(lists:member(bigmeck_test_target, meck:mocked())),
        ?assertError(bigmeck_storage_unavailable, bigmeck_test_target:fun_a()),
        erase('x-request-id'),
        ?assertError(bigmeck_storage_unavailable, bigmeck_test_target:fun_a()),
        ?assertEqual(ok, bigmeck:unload())
    end).

registration_validation_and_arity_test() ->
    with_mock(fun() ->
        ?assertError(
            {invalid_request_id, undefined},
            bigmeck:expect(bigmeck_test_target, fun_a, 0, mocked)
        ),
        put('x-request-id', invalid),
        ?assertError(
            {invalid_request_id, invalid},
            bigmeck:expect(bigmeck_test_target, fun_a, 0, mocked)
        ),
        put('x-request-id', <<"request-a">>),
        ?assertError(badarg, bigmeck:expect(bigmeck_test_target, fun_a, 21, mocked)),
        ?assertError(
            {undefined_function, {bigmeck_test_target, missing, 0}},
            bigmeck:expect(bigmeck_test_target, missing, 0, mocked)
        ),
        ?assertEqual([], ets:tab2list(bigmeck_expectations)),
        Other = bigmeck_no_debug_info_target,
        ok = meck:new(Other, [passthrough, non_strict]),
        try
            ok = bigmeck:expect(Other, many_arguments, 20, mocked),
            ?assertEqual(mocked, apply(Other, many_arguments, lists:seq(1, 20)))
        after
            ok = meck:unload(Other)
        end
    end).

with_mock(Test) ->
    ok = meck:new(bigmeck_test_target, [passthrough]),
    try
        Test()
    after
        erase('x-request-id'),
        ok = bigmeck:unload(),
        ok = meck:unload(bigmeck_test_target)
    end.
