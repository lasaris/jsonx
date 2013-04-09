%% @copyright 2013 Yuriy Iskra <iskra.yw@gmail.com>

%% @doc JSONX is an Erlang library for efficient decode and encode JSON, written in C.
%%      Works with binaries as strings, arrays as lists and it only knows how to decode UTF-8 (and ASCII).
%%
%%      <h3>Decode (json -> erlang)</h3>
%%      <ul>
%%       <li>null   -> atom null</li>
%%       <li>true   -> atom true</li>
%%       <li>false  -> atom false</li>
%%       <li>string -> binary</li>
%%       <li>number -> number</li>
%%       <li>array  -> list</li>
%%       <li>object -> {PropList}, optional struct or proplist.</li>
%%       <li>object -> #record{...} - decoder must be predefined</li>
%%      </ul>
%%      <h3>Encode (erlang -> json)</h3>
%%      <ul>
%%       <li>atom null 	      -> null</li>
%%       <li>atom true 	      -> true</li>
%%       <li>atom true 	      -> false</li>
%%       <li>any other atom     -> string</li>
%%       <li>binary             -> string</li>
%%       <li>number             -> number</li>
%%       <li>{struct, PropList} -> object</li>
%%       <li>{PropList}         -> object</li>
%%       <li>PropList           -> object</li>
%%       <li>#record{...}       -> object - encoder must be predefined</li>
%%       <li>{json, IOList}     -> include IOList with no validation</li>
%%      </ul>

-module(jsonx).
-export([encode/1, decode/1, decode/2, encoder/1, decoder/1]).
-on_load(init/0).
-define(LIBNAME, jsonx).
-define(APPNAME, jsonx).

%%@doc Encode JSON.
-spec encode(JSON_TERM) -> JSON when
      JSON      :: binary(),
      JSON_TERM :: any().
encode(_) ->
    not_loaded(?LINE).


%%@doc Decode JSON to Erlang term.
-spec decode(JSON) -> JSON_TERM when
      JSON      :: binary(),
      JSON_TERM :: any().
decode(JSON) ->
    decode_opt(JSON, eep18).

%%@doc Decode JSON to Erlang term with options.
-spec decode(JSON, OPTIONS) -> JSON_TERM when
      JSON      :: binary(),
      OPTIONS   :: [{format, struct|eep18|proplist}],
      JSON_TERM :: any().
decode(JSON, Options) ->
    decode_opt(JSON, parse_opt(Options)).

%% %% Records descriptions for encoder resource
%% {Rcnt                                  %% Records count
%%  ,Fcnt                                 %% Counter all fields in records
%%  ,Records = [{Tag, Fields_off, Arity}] %% List of records tag, position and length fields
%%  ,Fields  = [{Name_off, Size}]         %% List of position and size fields names in binary storage
%%  ,Binsz                                %% Binary data size
%%  ,Bin                                  %% Binary storage for names of fields, format - <,"name": >
%% }

%%@doc Build JSON encoder.
-spec encoder(RECORDS_DESC) -> ENCODER when
      RECORDS_DESC :: [{tag, [names]}],
      ENCODER      :: function().
encoder(Records_desc) ->
    {Rcnt, Fcnt, Binsz, Records, Fields, Bin} = prepare_enc_desc(Records_desc),
    Resource = make_encoder_resource(Rcnt, Fcnt, Records, Fields, Binsz, Bin),
    fun(JSON_TERM) -> encode_res(JSON_TERM, Resource) end.

%%@doc Build JSON decoder.
-spec decoder(RECORDS_DESC) -> DECODER when
      RECORDS_DESC :: [{tag, [names]}],
      DECODER      :: function().
decoder(Records_desc) ->
    %% _ = decode_res(1,2,3 ),
    %% _Opt = parse_opt(Options),
    {RecCnt, UKeyCnt, KeyCnt, UKeys, Keys, Records3} = prepare_for_dec(Records_desc),
    Resource = make_decoder_resource(RecCnt, UKeyCnt, KeyCnt, UKeys, Keys, Records3),
    %% {
    %%   Opt,
    %%   Resource
    %%  {RecCnt, UKeyCnt, KeyCnt, UKeys, Keys, Records3}
    %% }.
     fun(JSON_TERM) -> decode_res(JSON_TERM, eep18, Resource) end.
	    

%% Private, call NIF

decode_opt(_JSON, _OPTIONS) ->
    not_loaded(?LINE).

encode_res(_JSON_TERM, _RESOURCE) ->
    not_loaded(?LINE).

decode_res(_JSON_TERM, _OPTION, _RESOURCE) ->
    not_loaded(?LINE).

make_encoder_resource(_Rcnt, _Fcnt, _Records, _Fields, _Binsz, _Bin) ->
    not_loaded(?LINE).

make_decoder_resource(_RecCnt, _UKeyCnt, _KeyCnt, _UKeys, _Keys, _Records3) ->
    not_loaded(?LINE).

%% Internal

parse_opt([]) ->
    eep18;
parse_opt([{format, struct} | _]) ->
    struct;
parse_opt([{format, proplist} | _]) ->
    proplist;
parse_opt([{format, eep18} | _]) ->
    eep18.
%%%% Internal for decoder

prepare_for_dec(Records) ->
    RecCnt = length(Records),
    Records1 = lists:ukeysort(1,Records),
    RecCnt1 = length(Records1),
    case (RecCnt1 == RecCnt) of
	true ->
	    UKeys = lists:usort(lists:flatten([Ks || {_Tag, Ks} <- Records1])),
	    {UKeyCnt, EnumUKeys} = enumerate(UKeys),
	    Records2 = [{Tag, length(Keys), [ findpos(EnumUKeys, K) || K <- Keys] } || {Tag, Keys} <- Records1],
	    {KeyCnt, Records3, Keys} = scan_records(Records2),
	    { RecCnt         %% Records Counter
	      , UKeyCnt      %% Uniq Keys Counter
	      , KeyCnt       %% Keys Counter
	      , UKeys        %% [Key]
	      , Keys         %% [KeyNum] 
	      , Records3     %% [{Tag, Off, Len}]
	    };
	false ->
	    {error, invalid_input}
    end.

scan_records(Records2) ->
    scan_records({0, [], []}, Records2).
scan_records({Offs, AccR, AccK}, []) ->
    {Offs, lists:reverse(AccR),  lists:reverse(AccK)};
scan_records({Offs, AccR, AccK}, [{Tag, Len, KeyNums} | Ts]) ->
    scan_records({Offs + Len, [{Tag, Offs, Len} | AccR], lists:reverse(KeyNums, AccK)}, Ts).

findpos(EnumKeys, Key) ->
    {Num, _Key} = lists:keyfind(Key, 2, EnumKeys),
    Num.

enumerate(Xs) ->
    enumerate(0, [], Xs ).
enumerate(N, Acc, []) ->
    {N, lists:reverse(Acc)};
enumerate(N, Acc, [H| Ts]) ->
    enumerate(N + 1, [{N, H} | Acc], Ts).

%%%% Internal for encoder
 
prepare_enc_desc(T) ->
    {Rcnt, Fcnt, Records, {Fields, Blen, Bins}} = prepare_enc_desc1(T),
    {Rcnt, Fcnt, Blen, lists:reverse(Records), lists:reverse(Fields),
     iolist_to_binary(lists:reverse(Bins))}.
prepare_enc_desc1(Records) ->
    prepare_enc_desc2(Records, {_Rcnt = 0, _OffF = 0, _Records = [],
	    {_Fields = [], _OffB = 0, _Bins = []}}).
prepare_enc_desc2([], R) ->
    R;
prepare_enc_desc2([{Tag, Fields} | RTail], {Rcnt, OffF, Records, FieldsR}) when is_atom(Tag) ->
    Fcnt = length(Fields),
    prepare_enc_desc2(RTail, {Rcnt+1, OffF + Fcnt, [{Tag,  OffF, Fcnt} | Records] , prepare_enc_fields1(Fields, FieldsR)}).
prepare_enc_fields1([], R) ->
    R;
prepare_enc_fields1( [Name|NTail], {Fields, OffB, Bins}  ) when is_atom(Name) ->
    Bin = iolist_to_binary(["\"", atom_to_binary(Name, latin1),<<"\": ">>]),
    LenB = size(Bin),
    prepare_enc_fields(NTail, {[{OffB, LenB} | Fields], OffB + LenB, [Bin|Bins]}).
prepare_enc_fields([], R) ->
    R;
prepare_enc_fields( [Name|NTail], {Fields, OffB, Bins}  ) when is_atom(Name) ->
    Bin = iolist_to_binary([",\"", atom_to_binary(Name, latin1),<<"\": ">>]),
    LenB = size(Bin),
    prepare_enc_fields(NTail, {[{OffB, LenB} | Fields], OffB + LenB, [Bin|Bins]}).

%% Init

init() ->
    So = case code:priv_dir(?APPNAME) of
        {error, bad_name} ->
            case filelib:is_dir(filename:join(["..", priv])) of
                true ->
                    filename:join(["..", priv, ?LIBNAME]);
                _ ->
                    filename:join([priv, ?LIBNAME])
            end;
        Dir ->
            filename:join(Dir, ?LIBNAME)
    end,
    erlang:load_nif(So, [[json, struct, proplist, eep18, no_match], [true, false, null],
			 [error, big_num, invalid_string, invalid_json, trailing_data]]).

not_loaded(Line) ->
    exit({not_loaded, [{module, ?MODULE}, {line, Line}]}).
