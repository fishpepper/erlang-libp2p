-module(libp2p_swarm_sup).

-behaviour(supervisor).

% supervisor
-export([init/1, start_link/1]).
% api
-export([sup/1, opts/1, name/1, address/1,
         register_server/1, server/1,
         register_group_agent/1, group_agent/1,
         register_peerbook/1, peerbook/1,
         register_cache/1, cache/1
         ]).

-define(SUP, swarm_sup).
-define(SERVER, swarm_server).
-define(PEERBOOK, swarm_peerbook).
-define(CACHE, swarm_cache).
-define(GROUP_AGENT, swarm_group_agent).
-define(ADDRESS, swarm_address).
-define(NAME, swarm_name).
-define(OPTS, swarm_opts).

start_link(Args) ->
    supervisor:start_link(?MODULE, Args).

init([Name, Opts]) ->
    inert:start(),
    TID = ets:new(Name, [public, ordered_set, {read_concurrency, true}]),
    ets:insert(TID, {?SUP, self()}),
    ets:insert(TID, {?NAME, Name}),
    ets:insert(TID, {?OPTS, Opts}),
    % Get or generate our keys
    {PubKey, SigFun} = init_keys(Opts),
    ets:insert(TID, {?ADDRESS, libp2p_crypto:pubkey_to_address(PubKey)}),

    SupFlags = {one_for_all, 3, 10},
    ChildSpecs = [
                  {listeners,
                   {libp2p_swarm_listener_sup, start_link, [TID]},
                   permanent,
                   10000,
                   supervisor,
                   [libp2p_swarm_listener_sup]
                  },
                  {sessions,
                   {libp2p_swarm_session_sup, start_link, [TID]},
                   permanent,
                   10000,
                   supervisor,
                   [libp2p_swarm_session_sup]
                  },
                  {transports,
                   {libp2p_swarm_transport_sup, start_link, [TID]},
                   permanent,
                   10000,
                   supervisor,
                   [libp2p_swarm_transport_sup]
                  },
                  {groups,
                   {libp2p_swarm_group_sup, start_link, [TID]},
                   permanent,
                   10000,
                   supervisor,
                   [libp2p_swarm_group_sup]
                  },
                  {?SERVER,
                   {libp2p_swarm_server, start_link, [TID, SigFun]},
                   permanent,
                   10000,
                   worker,
                   [libp2p_swarm_server]
                  },
                  {?PEERBOOK,
                   {libp2p_peerbook, start_link, [TID, SigFun]},
                   permanent,
                   10000,
                   worker,
                   [libp2p_peerbook]
                  },
                  {?CACHE,
                   {libp2p_cache, start_link, [TID]},
                   permanent,
                   10000,
                   worker,
                   [libp2p_cache]
                  },
                  {relay,
                   {libp2p_relay_server, start_link, [TID]},
                   permanent,
                   10000,
                   worker,
                   [libp2p_relay_server]
                  }
                 ]
                 ++ group_agent_spec(Opts, TID)
                 ++ include_proxy(TID, Opts),
    {ok, {SupFlags, ChildSpecs}}.


-spec init_keys(libp2p_swarm:swarm_opts()) -> {libp2p_crypto:public_key(), libp2p_crypto:sig_fun()}.
init_keys(Opts) ->
    case libp2p_config:get_opt(Opts, key, false) of
        false ->
            {PrivKey, PubKey} = libp2p_crypto:generate_keys(),
            {PubKey, libp2p_crypto:mk_sig_fun(PrivKey)};
        {PubKey, SigFun} -> {PubKey, SigFun}
    end.

-spec group_agent_spec(libp2p_swarm:swarm_opts(), ets:tab()) -> [supervisor:child_spec()].
group_agent_spec(Opts, TID) ->
    AgentModule = libp2p_config:get_opt(Opts, group_agent, libp2p_group_gossip),
    [AgentModule:group_agent_spec(?GROUP_AGENT, TID)].

include_proxy(TID, Opts) ->
    case {libp2p_proxy:address(Opts) ,libp2p_proxy:port(Opts)} of
        {undefined, _} -> [];
        {_, undefined} -> [];
        {Address, Port} ->
            [{
                proxy
                ,{libp2p_proxy_server, start_link, [[TID, Address, Port]]}
                ,permanent
                ,10000
                ,worker
                ,[libp2p_proxy_server]
            }]
    end.

-spec sup(ets:tab()) -> pid().
sup(TID) ->
    ets:lookup_element(TID, ?SUP, 2).

register_server(TID) ->
    ets:insert(TID, {?SERVER, self()}).

-spec server(ets:tab() | pid()) -> pid().
server(Sup) when is_pid(Sup) ->
    Children = supervisor:which_children(Sup),
    {?SERVER, Pid, _, _} = lists:keyfind(?SERVER, 1, Children),
    Pid;
server(TID) ->
    ets:lookup_element(TID, ?SERVER, 2).

register_peerbook(TID) ->
    ets:insert(TID, {?PEERBOOK, self()}).

-spec peerbook(ets:tab()) -> pid().
peerbook(TID) ->
    ets:lookup_element(TID, ?PEERBOOK, 2).

register_cache(TID) ->
    ets:insert(TID, {?CACHE, self()}).

-spec cache(ets:tab()) -> pid().
cache(TID) ->
    ets:lookup_element(TID, ?CACHE, 2).

-spec address(ets:tab()) -> libp2p_crypto:address().
address(TID) ->
    ets:lookup_element(TID, ?ADDRESS, 2).

-spec name(ets:tab()) -> atom().
name(TID) ->
    ets:lookup_element(TID, ?NAME, 2).

-spec opts(ets:tab()) -> libp2p_config:opts() | any().
opts(TID) ->
    case ets:lookup(TID, ?OPTS) of
        [{_, Opts}] -> Opts;
        [] -> []
    end.

-spec group_agent(ets:tab()) -> pid().
group_agent(TID) ->
    ets:lookup_element(TID, ?GROUP_AGENT, 2).

register_group_agent(TID) ->
    ets:insert(TID, {?GROUP_AGENT, self()}).
