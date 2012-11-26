    ****************************************************************************    
    * Copyright © 2011-2012 xjm (xiejianming@gmail.com)
    *
    * License: MIT license(http://www.opensource.org/licenses/mit-license.html), 
    * just the same as Lua(http://www.lua.org/)
    ****************************************************************************

lua_nrepl_client
================

This is a Clojure nREPL client written in Lua. It implements almost all OP codes of Clojure nREPL messages(except for ":load-file" & ":interrupt").

Please be aware of this implementation uses nREPL's default encoding "bencode" to encode/decode messages between the client and nREPL server.

0. 	PREPARE:
================
Have your nREPL server started; make sure files clj_client.lua & bencode.lua are under your lua path.
    
1. 	RUN:
================
In the Lua console, type following:
    a) "cljc=require("clj_client").start_clj_client"
    b) "cljc(host,port)" -- remember to replace the host & port to your real nREPL environment 

2.  PLAY:
================
Once you see a prompt like "user=>: ", you can try typing some Clojure codes to send(e.g. "*ns*").

User input starting with an exclamation mark(!) means special command. Special commands are usually special nREPL OPerations(e.g. "!sessions" for ":sessions" OP), or configuration command(e.g. "!timeout 0.1" is to set timeout to 0.1 second), or, to make it's more interesting, I just had it also kind of Lua code executable under "!". 

To sum up:
    * ! - list current configurations
    * !q - quite client
    * !sessions - list active sessions on nREPL server
    * !ver - list nREPL version info
    * !ops - list nREPL supported OPs
    * !showraw - switch to/not-to show non-decoded messages received from server
    * !shownaked - switch to/not-to show non-explained messages received from server
    * !timeout xx - set timeout to xx seconds (when waiting for server's response)
    * !retries xx - set retries to xx times (when waiting for server's response)
    * !some-lua-code - try to execute Lua code

I just wrote this tool for fun & to study some new things, so I may not update this small kit that frequently. 

If you have any ideas or requirements(or found any bugs), please just let me know (yes I will try to solve them).

Have Fun!