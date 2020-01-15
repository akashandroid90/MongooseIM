-module(mongoose_cluster_id).
-compile([export_all]).

-include("mongoose.hrl").

-export([
         start/0,
         get_cluster_id/0,
         get_backend_cluster_id/0
        ]).

-export([which_backend_available/0]).

-record(mongoose_cluster_id, {key :: atom(), value :: cluster_id()}).
-type cluster_id() :: binary().
-type mongoose_backend() :: rdbms
                          % | cassandra
                          % | elasticsearch
                          % | riak
                          | mnesia.

-spec start() -> ok | {error, any()}.
start() ->
    init_mnesia_cache(),
    run_monad(
     [fun get_cluster_id/0,
      fun get_backend_cluster_id/0,
      fun make_and_set_new_cluster_id/0]).

run_monad(Funs) ->
    run_monad(Funs, undefined).

run_monad([Fun | NextFuns], undefined) ->
    run_monad(NextFuns, Fun());
run_monad([Fun | NextFuns], {error, _} = Error) ->
    ?WARNING_MSG("mongoose_cluster_id:start/0 failed with error ~p", [Error]),
    run_monad(NextFuns, Fun());
run_monad(_, {ok, ID}) when is_binary(ID) ->
    ok.

%% Get cached version
-spec get_cluster_id() -> {ok, cluster_id()} | {error, any()}.
get_cluster_id() ->
    T = fun() -> mnesia:read(mongoose_cluster_id, cluster_id) end,
    case mnesia:transaction(T) of
        {atomic, [#mongoose_cluster_id{value = ClusterID}]} ->
            {ok, ClusterID};
        {atomic, []} ->
            {error, cluster_id_not_created};
        {aborted, Reason} ->
            {error, Reason}
    end.

-spec get_backend_cluster_id() -> {ok, cluster_id()} | {error, any()}.
get_backend_cluster_id() ->
    get_cluster_id_from_backend(which_backend_available()).

-spec make_and_set_new_cluster_id() -> {ok, cluster_id()} | {error, any()}.
make_and_set_new_cluster_id() ->
    NewID = make_cluster_id(),
    case set_new_cluster_id(NewID) of
        {error, _} = Err -> Err;
        ok -> cache_cluster_id(NewID), {ok, NewID}
    end.

%% ====================================================================
%% Internal functions
%% ====================================================================
init_mnesia_cache() ->
    mnesia:create_table(mongoose_cluster_id,
                        [{type, set},
                         {record_name, mongoose_cluster_id},
                         {attributes, record_info(fields, mongoose_cluster_id)},
                         {disc_only_copies, [node()]}
                        ]),
    mnesia:add_table_copy(mongoose_cluster_id, node(), ram_copies).

-spec cache_cluster_id(cluster_id()) -> ok | {error, any()}.
cache_cluster_id(ID) ->
    T = fun() -> mnesia:write(#mongoose_cluster_id{key = cluster_id, value = ID}) end,
    case mnesia:transaction(T) of
        {atomic, ok} ->
            ok;
        {aborted, Reason} ->
            {error, Reason}
    end.

-spec make_cluster_id() -> cluster_id().
make_cluster_id() ->
    uuid:uuid_to_string(uuid:get_v4(), binary_standard).

%% Which backend is enabled
-spec which_backend_available() -> mongoose_backend().
which_backend_available() ->
    try
        is_rdbms_enabled() andalso throw({backend, rdbms}),
        % is_cassandra_enabled() andalso throw({backend, cassandra}),
        % is_elasticsearch_enabled() andalso throw({backend, elasticsearch}),
        % is_riak_enabled() andalso throw({backend, riak}),
        mnesia
    catch
        {backend, B} -> B
    end.

is_rdbms_enabled() ->
    mongoose_rdbms:db_engine(<<>>) =/= undefined.
% is_cassandra_enabled() ->
    % mongoose_wpool:is_configured(cassandra).
% is_elasticsearch_enabled() ->
    % case catch mongoose_elasticsearch:health() of
        % {ok, _} -> true;
        % _ -> false
    % end.
% is_riak_enabled() ->
    % case catch mongoose_riak:list_buckets(<<"default">>) of
        % {ok, '_'} -> true;
        % _ -> false
    % end.

%% Set cluster ID
-spec set_new_cluster_id(cluster_id()) -> ok | {error, binary()}.
set_new_cluster_id(ID) ->
    set_new_cluster_id(ID, which_backend_available()).

-spec set_new_cluster_id(cluster_id(), mongoose_backend()) -> ok | {error, binary()}.
set_new_cluster_id(ID, rdbms) ->
    SQLQuery = [<<"INSERT INTO mongoose_cluster_id(key,value) "
                  "VALUES (\'cluster_id\',">>,
                mongoose_rdbms:use_escaped(mongoose_rdbms:escape_string(ID)), ");"],
    try mongoose_rdbms:sql_query(?MYNAME, SQLQuery) of
        {updated, 1} -> ok;
        {error, _} = Err -> Err
    catch
        E:R:Stack ->
            ?WARNING_MSG("issue=error_reading_cluster_id_from_rdbms, class=~p, reason=~p, stack=~p",
                         [E, R, Stack]),
            {error, {E,R}}
    end;
% set_new_cluster_id(_ID, cassandra) ->
%     ok;
% set_new_cluster_id(_ID, elasticsearch) ->
%     ok;
% set_new_cluster_id(_ID, riak) ->
%     ok;
set_new_cluster_id(ID, mnesia) ->
    cache_cluster_id(ID).

%% Get cluster ID
-spec get_cluster_id_from_backend(mongoose_backend()) ->
    {ok, cluster_id()} | {error, binary()}.
get_cluster_id_from_backend(rdbms) ->
    SQLQuery = [<<"SELECT value FROM mongoose_cluster_id WHERE \"key\"=\"cluster_id\" LIMIT 1">>],
    try mongoose_rdbms:sql_query(?MYNAME, SQLQuery) of
        {selected, [{Row}]} -> {ok, Row};
        {selected, []} -> {error, no_value};
        {error, _} = Err -> Err
    catch
        E:R:Stack ->
            ?WARNING_MSG("issue=error_reading_cluster_id_from_rdbms, class=~p, reason=~p, stack=~p",
                         [E, R, Stack]),
            {error, <<>>}
    end;
% get_cluster_id_from_backend(cassandra) ->
%     {ok, <<>>};
% get_cluster_id_from_backend(elasticsearch) ->
%     {ok, <<>>};
% get_cluster_id_from_backend(riak) ->
%     {ok, <<>>};
get_cluster_id_from_backend(mnesia) ->
    get_cluster_id().

