-module(bigmeck).
-moduledoc """
Request-scoped literal return values on top of Meck.

Store a binary request ID under the process dictionary atom 'x-request-id'
when registering expectations and in each process calling a mocked function.
""".

-export([expect/4, unload/0]).

% Keep failure-path test access out of the public library API.
-ifdef(TEST).
-export([await_table/3, own_table/1]).
-endif.

-define(TABLE, bigmeck_expectations).

-doc """
Register a literal return value for the current request ID and target.

Supports arities 0 through 20. The first registration lazily starts shared ETS
storage. Calls without a matching entry pass through to the original function.
""".
-spec expect(Module, Function, Arity, ReturnValue) -> Return when
    Module :: module(),
    Function :: atom(),
    Arity :: 0..20,
    ReturnValue :: term(),
    Return :: ok.
expect(Module, Function, Arity, ReturnValue) when
    is_atom(Module), is_atom(Function), is_integer(Arity), Arity >= 0, Arity =< 20
->
    RequestId = request_id(),
    Table = ensure_table(),
    Handler = fun(Arguments) ->
        lookup(Table, {get('x-request-id'), Module, Function, Arity}, Arguments)
    end,
    ok = meck:expect(Module, Function, callback(Arity, Handler)),
    true = ets:insert(Table, {{RequestId, Module, Function, Arity}, ReturnValue}),
    ok;
expect(_Module, _Function, _Arity, _ReturnValue) ->
    error(badarg).

-doc "Stop the ETS owner and discard its table, leaving Meck mocks untouched.".
-spec unload() -> Return when
    Return :: ok.
unload() ->
    case ets:info(?TABLE, owner) of
        undefined ->
            ok;
        Owner ->
            Monitor = monitor(process, Owner),
            exit(Owner, shutdown),
            receive
                {'DOWN', Monitor, process, Owner, _Reason} -> ok
            after 5000 ->
                demonitor(Monitor, [flush]),
                error(bigmeck_owner_timeout)
            end
    end.

request_id() ->
    case get('x-request-id') of
        RequestId when is_binary(RequestId) -> RequestId;
        Invalid -> error({invalid_request_id, Invalid})
    end.

ensure_table() ->
    case ets:whereis(?TABLE) of
        undefined ->
            Caller = self(),
            % ETS deletes a table when its owner exits, so a separate process
            % keeps shared expectations alive after this caller exits.
            {Owner, Monitor} = spawn_monitor(fun() -> own_table(Caller) end),
            % Spawning is asynchronous; wait for the table before using it.
            await_table(Owner, Monitor, 5000);
        Table ->
            Table
    end.

await_table(Owner, Monitor, Timeout) ->
    receive
        {Owner, ready, Table} ->
            demonitor(Monitor, [flush]),
            Table;
        {'DOWN', Monitor, process, Owner, normal} ->
            ensure_table();
        {'DOWN', Monitor, process, Owner, Reason} ->
            error({bigmeck_owner_start_failed, Reason})
    after Timeout ->
        demonitor(Monitor, [flush]),
        error(bigmeck_owner_timeout)
    end.

own_table(Caller) ->
    try ets:new(?TABLE, [named_table, public, set, {read_concurrency, true}]) of
        _Name ->
            Caller ! {self(), ready, ets:whereis(?TABLE)},
            timer:sleep(infinity)
    catch
        % Another concurrent registration may have created the table first.
        error:badarg -> ok
    end.

lookup(Table, Key, Arguments) ->
    Entries =
        try
            ets:lookup(Table, Key)
        catch
            error:badarg -> error(bigmeck_storage_unavailable)
        end,
    case Entries of
        [{Key, ReturnValue}] -> ReturnValue;
        [] -> meck:passthrough(Arguments)
    end.

callback(Arity, Handler) ->
    Annotation = erl_anno:new(0),
    Variables = [
        {var, Annotation, list_to_atom("A" ++ integer_to_list(Index))}
     || Index <- lists:seq(1, Arity)
    ],
    Arguments = lists:foldr(
        fun(Variable, Tail) -> {cons, Annotation, Variable, Tail} end,
        {nil, Annotation},
        Variables
    ),
    Call = {call, Annotation, {var, Annotation, 'Handler'}, [Arguments]},
    Expression = {'fun', Annotation, {clauses, [{clause, Annotation, Variables, [], [Call]}]}},
    Bindings = erl_eval:add_binding('Handler', Handler, erl_eval:new_bindings()),
    {value, Callback, _Bindings} = erl_eval:expr(Expression, Bindings),
    Callback.
