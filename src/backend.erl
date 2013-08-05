-module(backend).
-export([start/0, stop/0]).

-define(SERVER_HOST, "localhost").
-define(SERVER_PORT, 8989).
-define(WS_TEXT_MSG, 129).


start() ->
	{ok, Listen} = gen_tcp:listen(?SERVER_PORT, [binary,
								  {packet, 0},
								  {reuseaddr, true},
								  {active, true}]),

	register(backend_acceptor, spawn(fun() -> par_connect(Listen) end)),

	register(client_manager, spawn(fun() -> manage_clients([]) end)).


stop() ->
	case whereis(backend_acceptor) of
		undefined ->
			ok;
		Pid ->
			exit(Pid, stop)
	end,

	client_manager ! stop.


par_connect(Listen) ->
	{ok, Socket} = gen_tcp:accept(Listen),
	
	spawn(fun() -> par_connect(Listen) end),
	client_manager ! {connect, Socket},

	wait(Socket).


loop(Socket) ->
	receive
		{tcp, Socket, Data} ->
			io:format("data received: ~p~n", [Data]),
			client_manager ! {data, Socket, decode_data(Data)},
			loop(Socket);
		{tcp_closed, Socket} ->
			client_manager ! {disconnect, Socket};
		Any ->
			io:format("LOOP FIXME: ~p~n",[Any]),
			loop(Socket)
		end.


manage_clients(Sockets) ->
	receive
		{gpio_set, {Pin, Value}} ->
			Str = io_lib:format("gpio_set-~p-~p", [Pin, Value]),
			io:format("gpio_set cmd: ~s~n", [Str]),
			send_data(Sockets, Str),
			manage_clients(Sockets);
		{pwm_set, {Pin, Value}} ->
			Str = io_lib:format("pwm_set-~p-~p", [Pin, Value]),
			io:format("pwm_set cmd: ~s~n", [Str]),
			send_data(Sockets, Str),
			manage_clients(Sockets);
		{connect, Socket} ->
			io:format("Socket connected: ~w~n", [Socket]),
			manage_clients([Socket | Sockets]);
		{disconnect, Socket} ->
			io:format("Socket disconnected: ~w~n", [Socket]),
			manage_clients(lists:delete(Socket, Sockets));
		{data, User, Data} ->
			User,
			send_data(Sockets, Data),
			manage_clients(Sockets);
		stop ->
			ok;
		_Unknown ->
			exit("ERROR: Unknown command")
	end.


send_data(Sockets, Data) ->
	SendData = fun(Socket) ->
				   DataBin = list_to_binary(Data),
				   Len = size(DataBin),
				   gen_tcp:send(Socket, [?WS_TEXT_MSG, Len, DataBin])
			   end,

	lists:foreach(SendData, Sockets).


handshake_hash(Key) ->
	base64:encode_to_string(crypto:sha(Key ++ "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")).


wait(Socket) ->
	receive
		{tcp, Socket, Bin} ->
			Data = binary_to_list(Bin),
		{match, [{StartOrigin, LengthOrigin}]} = re:run(Data, "Origin: [^\r]*"),
			Origin = string:substr(Data, StartOrigin+9, LengthOrigin-8),
		{match, [{StartKey, LengthKey}]} = re:run(Data, "Sec-WebSocket-Key: [^\r]*"),
			Key = string:substr(Data, StartKey+20, LengthKey-19),
			Resp = "HTTP/1.1 101 Web Socket Protocol Handshake\r\n" ++
				   "Upgrade: WebSocket\r\n" ++
				   "Connection: Upgrade\r\n" ++
				   "WebSocket-Origin: " ++ Origin ++ "\r\n" ++
				   "WebSocket-Location: ws://" ++ ?SERVER_HOST ++ ":" ++ integer_to_list(?SERVER_PORT) ++  "/\r\n" ++
				   "Sec-WebSocket-Accept: " ++ handshake_hash(Key) ++ "\r\n\r\n",
			gen_tcp:send(Socket, Resp),
			loop(Socket);
		Any ->
			io:format("WAIT FIXME: ~p~n",[Any]),
			wait(Socket)
	end.


decode_data(<<?WS_TEXT_MSG:8, 255:8, Len:64, Masks:32, Payload/binary>>) ->
	io:format("Got a very big one: len=~p - ~p~n", [Len, Payload]),
	Data = list_to_binary(decode_payload(Masks, Payload)),
	handle_data(Len, Data );


decode_data(<<?WS_TEXT_MSG:8, 254:8, Len:16, Masks:32, Payload/binary>>) ->
	io:format("Got a big one: len=~p - (~p) ~p~n", [Len, byte_size(Payload), Payload]),
	Data = list_to_binary(decode_payload(Masks, Payload)),
	handle_data(Len, Data);


decode_data(<<?WS_TEXT_MSG:8, EncLen:8, Masks:32, Payload0/binary>>) ->
	Len = EncLen band 127,
	<<Payload:Len/bytes>> = Payload0,
	io:format("Got a short one: len=~p, Masks=~p, Payload=~p~n", [Len, Masks, Payload]),
	Data = list_to_binary(decode_payload(Masks, Payload)),
	handle_data(Len, Data).


decode_payload(Masks, Payload) when byte_size(Payload) < 4 ->
	Len = byte_size(Payload),
	<<PD:Len/integer-unit:8>> = Payload,
	<<NewMasks:Len/integer-unit:8, _/binary>> = <<Masks:32>>,
	[<< (PD bxor NewMasks):Len/integer-unit:8 >>];


decode_payload(Masks, Payload) ->
	<<PD:4/integer-unit:8, Rest/binary>> = Payload,
	[<<(PD bxor Masks):4/integer-unit:8>>| decode_payload(Masks, Rest)]. 


handle_data(Len, Data) ->
	%%parse_cmd:execute(binary_to_list(Data)),
	io:format("received: text message with len:~p -  ~p~n", [Len ,Data]),

	binary_to_list(Data).

