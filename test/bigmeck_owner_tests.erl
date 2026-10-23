-module(bigmeck_owner_tests).

-include_lib("eunit/include/eunit.hrl").

-doc """
Verify that a competing owner exits when the named ETS table already exists
and that initialization returns the existing table without changing its owner.
""".
concurrent_owner_creation_test() ->
    Table = ets:new(bigmeck_expectations, [named_table, public]),
    try
        Caller = self(),
        {Owner, Monitor} = spawn_monitor(fun() -> bigmeck:own_table(Caller) end),
        ?assertEqual(ets:whereis(Table), bigmeck:await_table(Owner, Monitor, 1000)),
        ?assertEqual(self(), ets:info(Table, owner))
    after
        ets:delete(Table)
    end.

-doc """
Verify that an abnormal owner exit during startup is reported with its reason.
""".
owner_start_failure_test() ->
    {Owner, Monitor} = spawn_monitor(fun() -> exit(start_failed) end),
    ?assertError(
        {bigmeck_owner_start_failed, start_failed},
        bigmeck:await_table(Owner, Monitor, 1000)
    ).

-doc """
Verify that waiting for an unresponsive owner times out and removes the monitor.
""".
owner_start_timeout_test() ->
    {Owner, Monitor} = spawn_monitor(fun() -> timer:sleep(infinity) end),
    try
        ?assertError(bigmeck_owner_timeout, bigmeck:await_table(Owner, Monitor, 0)),
        ?assertNot(lists:member({process, Owner}, element(2, process_info(self(), monitors))))
    after
        stop_process(Owner)
    end.

-doc """
Verify that unload times out and removes its monitor when the ETS owner ignores
the shutdown signal. Allow enough time for the five-second API timeout.
""".
unload_timeout_test_() ->
    {timeout, 10, fun unload_timeout/0}.

unload_timeout() ->
    Caller = self(),
    Owner = spawn(fun() ->
        process_flag(trap_exit, true),
        ets:new(bigmeck_expectations, [named_table, public]),
        Caller ! {self(), ready},
        timer:sleep(infinity)
    end),
    try
        receive
            {Owner, ready} -> ok
        after 1000 ->
            error(owner_start_timeout)
        end,
        ?assertError(bigmeck_owner_timeout, bigmeck:unload()),
        ?assertNot(lists:member({process, Owner}, element(2, process_info(self(), monitors))))
    after
        stop_process(Owner)
    end.

stop_process(Pid) ->
    Monitor = monitor(process, Pid),
    exit(Pid, kill),
    receive
        {'DOWN', Monitor, process, Pid, _Reason} -> ok
    after 1000 ->
        error(process_stop_timeout)
    end.
