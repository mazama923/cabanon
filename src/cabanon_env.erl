-module(cabanon_env).
-export([required/1]).

required(Name) ->
    case os:getenv(Name) of
        false -> {error, nil};
        Value -> {ok, unicode:characters_to_binary(Value)}
    end.
