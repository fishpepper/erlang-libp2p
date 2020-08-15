-module(libp2p_group_gossip).

-type opt() :: {peerbook_connections, pos_integer()}
             | {drop_timeout, pos_integer()}
             | {stream_clients, [libp2p_group_worker:stream_client_spec()]}
             | {seed_nodes, [MultiAddr::string()]}.

-export_type([opt/0]).

-type handler() :: {Module::atom(), State::any()}.
-type connection_kind() :: peerbook | seed | inbound.

-export_type([handler/0, connection_kind/0]).

-export([add_handler/3, remove_handler/2, send/3, connected_addrs/2, connected_pids/2]).

-spec add_handler(pid(), string(), handler()) -> ok.
add_handler(Pid, Key, Handler) ->
    gen_server:cast(Pid, {add_handler, Key, Handler}, 45000).

-spec remove_handler(pid(), string()) -> ok.
remove_handler(Pid, Key) ->
    gen_server:call(Pid, {remove_handler, Key}, 45000).

%% @doc Send the given data to all members of the group for the given
%% gossip key. The implementation of the group determines the strategy
%% used for delivery. Delivery is best effort.
-spec send(pid(), string(), iodata() | fun(() -> iodata())) -> ok.
send(Pid, Key, Data) when is_list(Key), is_binary(Data) orelse is_function(Data) ->
    gen_server:cast(Pid, {send, Key, Data}).

-spec connected_addrs(pid(), connection_kind() | all) -> [MAddr::string()].
connected_addrs(Pid, WorkerKind) ->
    gen_server:call(Pid, {connected_addrs, WorkerKind}, infinity).

-spec connected_pids(Pid::pid(), connection_kind() | all) -> [pid()].
connected_pids(Pid, WorkerKind) ->
    gen_server:call(Pid, {connected_pids, WorkerKind}, infinity).
