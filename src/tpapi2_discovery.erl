-module(tpapi2_discovery).
-export([get_nodes/2, update_json/0]).

-define(bootstrap, "https://raw.githubusercontent.com/thepower/all_chains/main/config.json").

read_bootstrap() ->
  {ok, CPid} = tpapi2:connect(?bootstrap),
  #{ path := Path }=uri_string:parse(?bootstrap),
  {200, _Headers, Bin} = tpapi2:do_get(CPid, Path),
  gun:close(CPid),
  jsx:decode(Bin,[return_maps]).

update_json() ->
  JSON=#{<<"chains">>:=AllChains} = read_bootstrap(),
  NewCh=maps:map(fun(ChainTxt,OldVal) ->
                      ChainNum=binary_to_integer(ChainTxt),
                      R=get_nodes(undefined, ChainNum),
                      if(is_map(R)) -> R;
                        true -> OldVal
                      end
                  end, AllChains),
  JSON#{<<"chains">> => NewCh}.

get_nodes(Network, Chain) ->
#{<<"settings">> := Nets, <<"chains">>:=AllChains} = read_bootstrap(),
    NetChains=maps:get(Network, Nets, []),
  ChainBin=integer_to_binary(Chain),
  case (Network==undefined orelse lists:member(Chain, NetChains)) andalso
       maps:is_key(ChainBin,AllChains) of
    true ->


      rand:seed(default),
      List=sort_peers(maps:get(ChainBin,AllChains)),
      rediscovery(List,Chain);
    false ->
      indir
  end.

rediscovery([Host|Rest],Chain) ->
  io:format("Getting from ~s~n",[Host]),
  case catch tpapi2:connect(Host) of
    {ok, ConnPid} ->
      {Code,Body}=try
                    Path="/api/nodes/"++integer_to_list(Chain)++".mp?bin=raw",
                    io:format("H ~p ~p~n",[Host, Path]),
                    {Code1, _, Body1} = tpapi2:do_get(ConnPid,Path),
                    {Code1, Body1}
                  catch _:_ ->
                          {error, <<>>}
                  after
                    gun:close(ConnPid)
                  end,
      try
        if Code==200 ->
             {ok,#{<<"chain_nodes">> := Nodes }}=msgpack:unpack(Body),
             Nodes;
           true ->
             if Rest == [] ->
                  {error, Code};
                true ->
                  rediscovery(Rest,Chain)
             end
        end
      catch _:_ ->
              if Rest == [] ->
                   {error, Code};
                 true ->
                   rediscovery(Rest,Chain)
              end
      end;
    Other ->
      if Rest == [] -> {error, Other};
         true -> rediscovery(Rest,Chain)
      end
  end.




sort_rnd(List) ->
  List0=[ {rand:uniform(), I} || I <- List ],
  List1=lists:keysort(1, List0),
  [ E || {_,E} <- List1 ].

sort_peers(List) ->
  {LL1,LL2}=maps:fold(
              fun(_,#{<<"ip">>:=V,<<"host">>:=H},{A1,A2}) ->
                  {
                   lists:foldl(
                     fun(Addr,A) ->
                         case uri_string:parse(Addr) of
                           #{scheme:= <<"http">>} ->
                             [Addr|A];
                           _ ->
                             A
                         end
                     end, A1, V),
                   lists:foldl(
                     fun(Addr,A) ->
                         case uri_string:parse(Addr) of
                           #{scheme:= <<"https">>} ->
                             [Addr|A];
                           _ ->
                             A
                         end
                     end, A2, H)}
              end, {[],[]},
              List
             ),
  rand:seed(default),
  sort_rnd(LL2)++sort_rnd(LL1).

