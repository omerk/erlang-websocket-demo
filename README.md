erlang-websocket-demo
=====================

A simple demo showcasing Erlang bit syntax used in handling protocols, using Websockets as an
example.

Please keep in mind that this is just a proof of concept demonstration. If you are thinking of
using Websockets in your project, you should probably look at
[Cowboy](https://github.com/extend/cowboy). 


# Instructions

Grab a copy of this demo:

    git clone https://github.com/omerk/erlang-websocket-demo.git && cd erlang-websocket-demo

Build and start an Erlang shell:

    make && make shell

Start backend:

    backend:start().

Fire up a browser and open `demo.htm`. Type in some text into the textbox and you should see it
echoed back by the backend.

