-module(bigmeck_tests).

-include_lib("eunit/include/eunit.hrl").

-doc """
Verify that only calls with a matching request ID receive the mocked value.
Missing, invalid, and unmatched IDs must use the original function.
""".
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

-doc """
Verify literal return values, replacement of an existing expectation, and
independent expectations for different modules and arities.
""".
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

-doc """
Verify that reset removes only the current request's expectations across targets.
Repeated resets preserve other requests, ETS ownership, and Meck mocks, and allow
expectations to be registered again.
""".
reset_request_isolation_test() ->
    with_mock(fun() ->
        Other = bigmeck_no_debug_info_target,
        try
            lists:foreach(
                fun(Id) ->
                    put('x-request-id', Id),
                    ok = bigmeck:expect(bigmeck_test_target, fun_a, 0, Id),
                    ok = bigmeck:expect(bigmeck_test_target, fun_a, 1, Id),
                    ok = bigmeck:expect(bigmeck_test_target, echo, 1, Id),
                    ok = bigmeck:expect(Other, fun_a, 0, Id)
                end,
                [<<"request-a">>, <<"request-b">>]
            ),
            Table = ets:whereis(bigmeck_expectations),
            Owner = ets:info(Table, owner),
            put('x-request-id', <<"request-a">>),
            ok = bigmeck:reset(),
            ok = bigmeck:reset(),
            ?assertEqual(original, bigmeck_test_target:fun_a()),
            ?assertEqual({original, argument}, bigmeck_test_target:fun_a(argument)),
            ?assertEqual(argument, bigmeck_test_target:echo(argument)),
            ?assertEqual(original, bigmeck_no_debug_info_target:fun_a()),
            ?assertEqual(Table, ets:whereis(bigmeck_expectations)),
            ?assertEqual(Owner, ets:info(Table, owner)),
            ?assert(lists:member(bigmeck_test_target, meck:mocked())),
            ?assert(lists:member(Other, meck:mocked())),
            put('x-request-id', <<"request-b">>),
            ?assertEqual(<<"request-b">>, bigmeck_test_target:fun_a()),
            ?assertEqual(<<"request-b">>, bigmeck_test_target:fun_a(argument)),
            ?assertEqual(<<"request-b">>, bigmeck_test_target:echo(argument)),
            ?assertEqual(<<"request-b">>, bigmeck_no_debug_info_target:fun_a()),
            ?assertEqual(4, ets:info(Table, size)),
            put('x-request-id', <<"request-a">>),
            ok = bigmeck:expect(bigmeck_test_target, fun_a, 0, registered_again),
            ?assertEqual(registered_again, bigmeck_test_target:fun_a())
        after
            ok = meck:unload(Other)
        end
    end).

-doc """
Verify that delete restores passthrough only for the current request and target.
Other modules, functions, arities, and requests remain mocked. Deleting missing
entries succeeds, and the deleted expectation can be registered again.
""".
delete_request_and_target_isolation_test() ->
    with_mock(fun() ->
        Other = bigmeck_no_debug_info_target,
        try
            put('x-request-id', <<"request-a">>),
            ok = bigmeck:expect(bigmeck_test_target, fun_a, 0, mocked),
            ok = bigmeck:expect(bigmeck_test_target, fun_a, 1, other_arity),
            ok = bigmeck:expect(bigmeck_test_target, echo, 1, other_function),
            ok = bigmeck:expect(Other, fun_a, 0, other_module),
            put('x-request-id', <<"request-b">>),
            ok = bigmeck:expect(bigmeck_test_target, fun_a, 0, other_request),
            put('x-request-id', <<"request-a">>),
            ok = bigmeck:delete(bigmeck_test_target, fun_a, 0),
            ok = bigmeck:delete(bigmeck_test_target, fun_a, 0),
            ok = bigmeck:delete(unmocked_module, missing, 20),
            ?assertEqual(original, bigmeck_test_target:fun_a()),
            ?assertEqual(other_arity, bigmeck_test_target:fun_a(argument)),
            ?assertEqual(other_function, bigmeck_test_target:echo(argument)),
            ?assertEqual(other_module, bigmeck_no_debug_info_target:fun_a()),
            ?assertEqual(4, ets:info(bigmeck_expectations, size)),
            ?assert(lists:member(bigmeck_test_target, meck:mocked())),
            put('x-request-id', <<"request-b">>),
            ?assertEqual(other_request, bigmeck_test_target:fun_a()),
            put('x-request-id', <<"request-a">>),
            ok = bigmeck:expect(bigmeck_test_target, fun_a, 0, registered_again),
            ?assertEqual(registered_again, bigmeck_test_target:fun_a())
        after
            ok = meck:unload(Other)
        end
    end).

-doc """
Verify that reset and delete succeed before any expectations are registered,
without creating ETS storage. An empty binary is a valid request ID.
""".
cleanup_without_storage_test() ->
    with_mock(fun() ->
        put('x-request-id', <<>>),
        ok = bigmeck:reset(),
        ok = bigmeck:delete(bigmeck_test_target, fun_a, 0),
        ?assertEqual(undefined, ets:whereis(bigmeck_expectations)),
        ?assertEqual(original, bigmeck_test_target:fun_a())
    end).

-doc """
Verify that reset and delete reject invalid request IDs and that delete rejects
invalid targets and unsupported arities without creating ETS storage.
""".
cleanup_validation_test() ->
    with_mock(fun() ->
        lists:foreach(
            fun(Id) ->
                put('x-request-id', Id),
                ?assertError({invalid_request_id, Id}, bigmeck:reset()),
                ?assertError(
                    {invalid_request_id, Id},
                    bigmeck:delete(bigmeck_test_target, fun_a, 0)
                )
            end,
            [undefined, invalid]
        ),
        put('x-request-id', <<"request-a">>),
        lists:foreach(
            fun({Module, Function, Arity}) ->
                ?assertError(badarg, bigmeck:delete(Module, Function, Arity))
            end,
            [
                {<<"module">>, fun_a, 0},
                {bigmeck_test_target, <<"function">>, 0},
                {bigmeck_test_target, fun_a, -1},
                {bigmeck_test_target, fun_a, 21},
                {bigmeck_test_target, fun_a, 1.0}
            ]
        ),
        ?assertEqual(undefined, ets:whereis(bigmeck_expectations))
    end).

-doc """
Verify that reset and delete preserve Meck history from multiple requests.
Subsequent passthrough calls extend that history and leave the mock valid.
""".
cleanup_preserves_meck_history_test() ->
    lists:foreach(
        fun(Cleanup) ->
            with_mock(fun() ->
                put('x-request-id', <<"request-a">>),
                ok = bigmeck:expect(bigmeck_test_target, fun_a, 0, mocked),
                ?assertEqual(mocked, bigmeck_test_target:fun_a()),
                put('x-request-id', <<"request-b">>),
                ?assertEqual(original, bigmeck_test_target:fun_a()),
                History = [
                    {self(), {bigmeck_test_target, fun_a, []}, mocked},
                    {self(), {bigmeck_test_target, fun_a, []}, original}
                ],
                ?assertEqual(History, meck:history(bigmeck_test_target)),
                put('x-request-id', <<"request-a">>),
                ok = Cleanup(),
                ?assertEqual(History, meck:history(bigmeck_test_target)),
                ?assertEqual(original, bigmeck_test_target:fun_a()),
                ?assertEqual(
                    History ++ [{self(), {bigmeck_test_target, fun_a, []}, original}],
                    meck:history(bigmeck_test_target)
                ),
                ?assert(meck:validate(bigmeck_test_target))
            end)
        end,
        [fun bigmeck:reset/0, fun() -> bigmeck:delete(bigmeck_test_target, fun_a, 0) end]
    ).

-doc """
Verify concurrent resets after all workers have registered their expectations.
Each worker's targets return to passthrough, an untouched request remains mocked,
and another process using a worker's request ID observes the same cleanup.
""".
parallel_reset_request_isolation_test() ->
    with_mock(fun() ->
        parallel_cleanup_request_isolation(fun bigmeck:reset/0, {original, argument})
    end).

-doc """
Verify concurrent deletes after all workers have registered their expectations.
Only the selected arity is removed for each worker's request. Other arities and
an untouched request remain mocked, with cleanup visible across processes.
""".
parallel_delete_request_isolation_test() ->
    with_mock(fun() ->
        parallel_cleanup_request_isolation(
            fun() -> bigmeck:delete(bigmeck_test_target, fun_a, 0) end,
            other_arity
        )
    end).

-doc """
Verify that unmatched calls pass their arguments to the original function and
propagate its errors, while matching requests receive their configured values.
""".
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

-doc """
Verify that concurrent registrations keep separate expectations for each request
and that shared ETS storage retains them after all registering workers exit.
""".
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

-doc """
Verify that unload removes ETS storage while leaving Meck mocks installed.
Installed callbacks report missing storage, and repeated unloading succeeds.
""".
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

-doc """
Verify registration errors for invalid IDs, unsupported arities, and undefined
functions, without storing failed expectations. Arity 20 remains supported.
""".
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

parallel_cleanup_request_isolation(Cleanup, ExpectedOtherArity) ->
    put('x-request-id', <<"untouched">>),
    ok = bigmeck:expect(bigmeck_test_target, fun_a, 0, untouched),
    ok = bigmeck:expect(bigmeck_test_target, fun_a, 1, untouched),
    Caller = self(),
    Ids = [integer_to_binary(Index) || Index <- lists:seq(1, 8)],
    Workers = [
        spawn_monitor(fun() ->
            put('x-request-id', Id),
            ok = bigmeck:expect(bigmeck_test_target, fun_a, 0, Id),
            ok = bigmeck:expect(bigmeck_test_target, fun_a, 1, other_arity),
            ?assertEqual(Id, bigmeck_test_target:fun_a()),
            ?assertEqual(other_arity, bigmeck_test_target:fun_a(argument)),
            Caller ! {self(), ready},
            receive
                go -> ok
            after 2000 ->
                error(worker_start_timeout)
            end,
            ok = Cleanup(),
            ?assertEqual(original, bigmeck_test_target:fun_a()),
            ?assertEqual(ExpectedOtherArity, bigmeck_test_target:fun_a(argument))
        end)
     || Id <- Ids
    ],
    try
        lists:foreach(
            fun({Pid, Monitor}) ->
                receive
                    {Pid, ready} -> ok;
                    {'DOWN', Monitor, process, Pid, Reason} -> error({worker_failed, Reason})
                after 2000 ->
                    error(worker_ready_timeout)
                end
            end,
            Workers
        ),
        % All registrations finish before any request starts cleaning up.
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
        ?assertEqual(untouched, bigmeck_test_target:fun_a()),
        ?assertEqual(untouched, bigmeck_test_target:fun_a(argument)),
        % Another process sharing each worker's ID sees the same cleanup.
        lists:foreach(
            fun(Id) ->
                put('x-request-id', Id),
                ?assertEqual(original, bigmeck_test_target:fun_a()),
                ?assertEqual(ExpectedOtherArity, bigmeck_test_target:fun_a(argument))
            end,
            Ids
        ),
        ?assert(meck:validate(bigmeck_test_target))
    after
        lists:foreach(
            fun({Pid, Monitor}) ->
                StopMonitor = monitor(process, Pid),
                exit(Pid, kill),
                receive
                    {'DOWN', StopMonitor, process, Pid, _Reason} -> ok
                after 2000 ->
                    error(worker_stop_timeout)
                end,
                demonitor(Monitor, [flush])
            end,
            Workers
        )
    end.

with_mock(Test) ->
    ok = meck:new(bigmeck_test_target, [passthrough]),
    try
        Test()
    after
        erase('x-request-id'),
        ok = bigmeck:unload(),
        ok = meck:unload(bigmeck_test_target)
    end.
