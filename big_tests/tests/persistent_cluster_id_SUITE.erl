-module(persistent_cluster_id_SUITE).

-include_lib("common_test/include/ct.hrl").

%% API
-export([all/0,
         suite/0,
         groups/0,
         init_per_suite/1,
         end_per_suite/1,
         group/1,
         init_per_group/2,
         end_per_group/2,
         init_per_testcase/2,
         end_per_testcase/2]).

%% test cases
-export([
         all_clustered_mongooses_report_the_same_client_id/1
        ]).

all() ->
    [
     {group, mnesia},
     {group, rdbms}
    ].

tests() ->
    [
     all_clustered_mongooses_report_the_same_client_id
    ].

suite() ->
    [{ct_hooks,[cth_surefire]}, {timetrap, {seconds, 30}}].

groups() ->
    [
     {mnesia, [], tests()},
     {rdbms, [], tests()}
    ].

%%%===================================================================
%%% Overall setup/teardown
%%%===================================================================
init_per_suite(Config) ->
    Config.

end_per_suite(_Config) ->
    ok.

%%%===================================================================
%%% Group specific setup/teardown
%%%===================================================================
group(_Groupname) ->
    [].

init_per_group(mnesia, Config) ->
    case not mongoose_helper:is_rdbms_enabled(domain()) of
        true -> Config;
        false -> {skip, require_no_rdbms}
    end;
init_per_group(_Groupname, Config) ->
    case mongoose_helper:is_rdbms_enabled(domain()) of
        true -> Config;
        false -> {skip, require_rdbms}
    end.

end_per_group(_Groupname, _Config) ->
    ok.

%%%===================================================================
%%% Testcase specific setup/teardown
%%%===================================================================
init_per_testcase(all_clustered_mongooses_report_the_same_client_id, Config) ->
    distributed_helper:add_node_to_cluster(distributed_helper:mim2(), Config),
    Config;
init_per_testcase(_TestCase, Config) ->
    Config.

end_per_testcase(all_clustered_mongooses_report_the_same_client_id, Config) ->
    distributed_helper:remove_node_from_cluster(distributed_helper:mim2(), Config),
    Config;
end_per_testcase(_TestCase, _Config) ->
    ok.

%%%===================================================================
%%% Individual Test Cases (from groups() definition)
%%%===================================================================
all_clustered_mongooses_report_the_same_client_id(_Config) ->
    {ok, ID_mim1} = mongoose_helper:successful_rpc(
               distributed_helper:mim(),
               mongoose_cluster_id, get_cluster_id, []),
    {ok, ID_mim2} = mongoose_helper:successful_rpc(
               distributed_helper:mim2(),
               mongoose_cluster_id, get_cluster_id, []),
    ct:log("ID for mim1 is ~p~n", [ID_mim1]),
    ct:log("ID for mim2 is ~p~n", [ID_mim2]),
    ID_mim1 = ID_mim2.

domain() ->
    ct:get_config({hosts, mim, domain}).
