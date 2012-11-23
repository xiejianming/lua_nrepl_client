--[[
	* Copyright © 2011-2012 xjm (xiejianming@gmail.com)
    *
    * License: MIT license(http://www.opensource.org/licenses/mit-license.html), 
    * just same as Lua(http://www.lua.org/)
]]

module("bencode",package.seeall)

-- ******************** enconding *********************************
function ben(item)
	local tp=type(item)
	local res
	if tp=="string" then
		return ""..#item..":"..item
	elseif tp=="number" then
		return "i"..item.."e"
	elseif tp=="list" then
		return list2ben(item)
	elseif tp=="dictionary" or tp=="table" then
		return dict2ben(item)
	else
		error("[BENCODE]Enconding ERR: Can't encode given item: "..item..". Type ["..tp.."] is not recognized!.")
	end
end

function list2ben(l)
	local res="l"
	for i=1,#l do
		res=res..ben(l[i])
	end
	return res.."e"
end
function dict2ben(d)
	local res="d"
	for k,v in pairs(d) do
		res=res..ben(k)..ben(v)
	end
	return res.."e"
end
-- ******************** deconding *********************************
function deben(s)
	if not s or #s==0 then return end
	local msgs=debencode(str2is(s))
	if type(msgs)~="table" then
		return {msgs}
	else
		return msgs
	end
end

-- read from a bencoded inputstream and parse it into items of a table
function debencode(inputstream)
	local is,t=inputstream,{}
	
	local c
	while true do
		c=is.read()
		if c=="d" then
			t[#t+1]=is_dict(is)
		elseif c=="l" then
			t[#t+1]=is_list(is)
		elseif c=="i" then
			t[#t+1]=is_int(is)
		elseif tonumber(c) then
			is.pushback()
			t[#t+1]=is_str(is)
		elseif c=="e" or c==nil then
			break
		else
			error("[BENCODE]Decoding ERR: Invalid encoding!!")
		end
	end
	
	if #t==1 then
		return t[1]
	else
		return t
	end
end

function is_dict(inputstream,pos)
	local dict=debencode(inputstream)
	local items=#dict
	if items%2~=0 then
		error("[BENCODE]Decoding ERR: A dictionary should have even number of items!")
	else
		local i,map=1,{}
		while i<items do
			map[dict[i]]=dict[i+1]
			i=i+2
		end
		local mtbl={__tostring=function(m)
									local tmp={}
									for k,v in pairs(m) do
										if type(v)=="string" then
											tmp[#tmp+1]=":"..tostring(k).." ".."\""..(v).."\""
										else
											tmp[#tmp+1]=":"..tostring(k).." "..tostring(v)
										end
										
									end
									if #tmp==0 then return "{}" end
									local str="{"..tmp[1]
									for i=2,#tmp do
										str=str..", "..tmp[i]
									end
									return str.."}"
								end,
					__type=function(l) return "dictionary" end}
		setmetatable(map,mtbl)
		return map
	end
end

function is_list(inputstream,pos)
	local list=debencode(inputstream)
	if type(list)~="table" then
		list={list}
	end
	local mtbl={__tostring=function(l)
								if #l==0 then return "[]" end
								local str
								if type(l[1])=="string" then
									str="[\""..l[1].."\""
								else
									str="["..l[1]
								end								
								for i=2,#l do
									if type(l[i])=="string" then
										str=str..", ".."\""..l[i].."\""
									else
										str=str..", "..tostring(l[i])
									end
								end
								return str.."]"
							end,
				__type=function(l) return "list" end}
	setmetatable(list,mtbl)
	return list
end

function is_int(inputstream)
	local int=""
	local c=inputstream.read()
	while c and c~="e" do
		int=int..c
		c=inputstream.read()
	end
	
	-- check if there's an ending 'e'
	inputstream.pushback()
	if inputstream.read()~="e" then
		error("[BENCODE]Decoding ERR: Invalid number encoding.")
	end
	
	return tonumber(int)
end

function is_str(inputstream)
	local len=""
	local c=inputstream.read()
	while c and c~=":" do
		len=len..c
		c=inputstream.read()
	end

	local str=""
	for i=1,tonumber(len) do
		c=inputstream.read()
		if c then 
			str=str..c
		else
			error("[BENCODE]Decoding ERR: Invalid string encoding.")
		end
	end

	return str
end

-- string to inputstream
function str2is(str)
	local fake_is={}
	for c in string.gmatch(str or "",".") do
		fake_is[#fake_is+1]=c
	end
	local pos=1
	return {
		read=function()
			pos=pos+1
			return fake_is[pos-1]
		end,
		pushback=function()
			pos=pos-1
		end,
		close=function()
			fake_is={}
		end,
		getraw=function()
			if #fake_is==0 then
				return nil
			else
				return str
			end
		end
	}
end