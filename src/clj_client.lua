--[[
	* Copyright © 2011-2012 xjm (xiejianming@gmail.com)
    *
    * License: MIT license(http://www.opensource.org/licenses/mit-license.html), 
    * just same as Lua(http://www.lua.org/)
]]

module("clj_client",package.seeall)

local b=require("bencode")

function start_clj_client(host,port)
	local socket=require("socket")
	local cnn,err=socket.connect(host or "localhost",port or 888)
	if not cnn then
		print(err)
		return
	end
	
	-- switch to turn on/off this client's options
		-- naked msg: original msg
		-- raw msg: bencoded msg
	local opts={showraw=false,shownaked=false,timeout=0.2,retries=5}
			
	-- get & set message ID
	local msg_id=0
	local function mid()
		msg_id=msg_id+1
		return tostring(msg_id-1)
	end
	
	-- send & get results from server
	local function evaluate(bencoded_str)
		if not bencoded_str then return end

		cnn:send(bencoded_str)
		
		resp,msgs=try_and_get(cnn,opts.timeout,opts.retries)
		
		if not msgs then return end
		
		if opts["showraw"] then					
			print(resp)
		end
		
		if opts["shownaked"] then
			for i=1,#msgs do
				print(msgs[i])
			end
		end			
			
		return msgs
	end		
	
	-- create session
	local id=mid()
	cnn:send("d2:id"..#id..":"..id.."2:op5:clonee")
	local resp=try_and_get(cnn,opts["timeout"],opts["retries"])	
	local status,msgs=pcall(b.deben,resp)
	if not msgs then 
		print("[clj-client]ERR: handshakes with nREPL failed.")
		cnn:close()
		return
	end

	local sid=msgs[1]["new-session"]
	local session="7:session"..#sid..":"..sid
	
	local ns="user"

	-- to handle special commands
	local function special_cmd(cmd)
		if cmd=="" then -- equals to "!" cmd
			print_table(opts)
		elseif cmd=="showraw" or cmd=="shownaked" then
			opts[cmd]=not opts[cmd]
		elseif string.sub(cmd,1,8)=="timeout " then
			opts["timeout"]=tonumber(string.sub(cmd,9))
		elseif string.sub(cmd,1,8)=="retries " then
			opts["retries"]=tonumber(string.sub(cmd,9))
		elseif cmd=="sessions" then
			local id=mid()
			print(get_sessions(evaluate("d2:id"..#id..":"..id.."2:op11:ls-sessionse")))
		elseif cmd=="ver" then
			local id=mid()
			local msgs=evaluate("d2:id"..#id..":"..id.."2:op8:describee")
			if not msgs then print("Can't get version info from server."); return end
			local ver=get_versions(msgs)
			print("nREPL v"..ver["nrepl"]["major"].."."..ver["nrepl"]["minor"].."."..ver["nrepl"]["incremental"])
			print("Clojre v"..ver["clojure"]["major"].."."..ver["clojure"]["minor"].."."..ver["clojure"]["incremental"])
		elseif cmd=="ops" then
			local id=mid()
			local msgs=evaluate("d2:id"..#id..":"..id.."2:op8:describee")
			if not msgs then print("Can't get ops info from server."); return end
			print(get_ops(msgs))
		elseif cmd=="kill" then
			-- interrupt last cmd sent
			
		elseif cmd=="load" then
			-- load file to nREPL server

		else
			-- evalute as Lua code
			if string.sub(cmd,1,1)=="=" then
				cmd="smart_print("..string.sub(cmd,2)..")"
			end
			local f,err=loadstring(cmd)
			if err then
				print(err)
			else
				local status,err=pcall(f)
				if not status then
					print(err)
				end
			end
		end
	end
	
	local input,trimed=""
	while true do
		io.write(ns.."=>: ")
		input=io.read()
		trimed=trim(input)
		if trimed=="!q" then
			cnn:send("d"..session.."2:op5:closee")
			cnn:close()
			break
		elseif string.sub(trimed,1,1)=="!" then
			special_cmd(string.sub(trimed,2))
		elseif trimed=="" then
			--no op
		else				
			id=mid()
			cnn:send("d2:id"..#id..":"..id..session.."2:op4:eval4:code"..#input..":"..input.."e")
			
			resp,msgs=try_and_get(cnn,opts.timeout,opts.retries)
			
			if not msgs then return end
			
			-- check to see if its a "need-input"
			if need_input(msgs) then				
				io.write(">>>: ")
				local cmd=io.read()				
				
				local old_id,new_id=id,mid()		
				cnn:send("d2:id"..#new_id..":"..new_id..session.."2:op5:stdin5:stdin"..(#cmd+1)..":"..cmd..string.format("\n").."e")								
				msgs={}
				while #msgs==0 do
					resp,msgs=try_and_get(cnn,opts.timeout,opts.retries)
					msgs=filter_by_id(msgs,tostring(old_id))
				end
			end
			
			if opts["showraw"] then					
				print(resp)
			end
			
			if opts["shownaked"] then
				for i=1,#msgs do
					print(msgs[i])
				end
			end			
			
			print(get_values(msgs) or is_err(msgs))			
						
			-- change ns when necessary
			ns=get_ns(msgs) or ns
		end
	end	
end

-- @depreciated
-- parse special items in a cmd
function parse(cmd)
	local new_cmd=string.gsub(cmd,"($${.-})", 
						function (s) 
							return assert(loadstring("return "..string.sub(s,4,-2)))() 
						end)							
	return new_cmd
end

-- filter msgs with given ID
function filter_by_id(msgs,id)
	local tmp={}
	for i=1, #msgs do
		if msgs[i]["id"]==id then
			tmp[#tmp+1]=msgs[i]
		end
	end
	
	return tmp
end

-- check to see if server needs user input
function need_input(msgs)
	local s
	for i=#msgs,1,-1 do
		s=msgs[i]["status"]
		if s then
			for j=1,#s do
				if s[j]=="need-input" then return true end
			end
		end
	end
end

-- read response from connection (in a wait & till mode)
-- in case we didn't receive complete messages from the server, we will try 'retries" times
	-- timeout: in seconds (default to 0.2 second)
	-- retries: times to retry (default to 3 times)
function get_response(cnn,timeout,retries)
	local recv,c,status=""
	cnn:settimeout(timeout or 0.2)

	for i=1,retries or 5 do
		if string.match(recv,"6:statusl") then
			return recv
		else
			while true do
				c,status=cnn:receive(1)
				if status=="timeout" then
					break
				else
					recv=recv..c
				end
			end
		end
	end
end

-- try and get response and then translate them into msgs
function try_and_get(cnn,timeout,retries)
	local resp=get_response(cnn,timeout,retries)
	local status,msgs=pcall(b.deben,resp)
	local ans
	while not status or not msgs do
		io.write("[clj-client]ERR: Can't get responses from nREPL.\nKeep waiting or quit?[enter \"no\" to quite]: ")
		ans=io.read()
		if ans=="no" then
			cnn:close()
			return
		end
		resp=(resp or "")..(get_response(cnn,timeout,retries) or "")
		status,msgs=pcall(b.deben,resp)
	end
	
	return resp,msgs
end

-- check if there's any internal errors(e.g. unknown-session)
function is_err(msgs)
	local status
	for i=#msgs,1,-1 do
		status=msgs[i]["status"]
		if status then
			for i=1,#status do
				if status[i]=="error" then
					return true
				end	
			end
		end
	end
	return false
end

-- get returned value of evaluation or any err
function get_values(msgs)
	local values=""
	for i=1,#msgs do
		-- print out value
		if msgs[i]["out"] then
			values=values..msgs[i]["out"]
		end
		-- value
		if msgs[i]["value"] then
			values=values..msgs[i]["value"].."\n"
		end
		-- or error
		if msgs[i]["err"] then
			values=values..msgs[i]["err"]
		end 
	end
	if values~="" then
		return values
	end
end

function get_ns(msgs)
	for i=1,#msgs do
		if msgs[i]["ns"] then
			return msgs[i]["ns"]
		end
	end
end

function get_sessions(msgs)
	for i=1,#msgs do
		if msgs[i]["sessions"] then
			return msgs[i]["sessions"]
		end
	end
end

function get_ops(msgs)
	for i=1,#msgs do
		if msgs[i]["ops"] then
			return msgs[i]["ops"]
		end
	end
end

function get_versions(msgs)
	for i=1,#msgs do
		if msgs[i]["versions"] then
			return msgs[i]["versions"]
		end
	end
end