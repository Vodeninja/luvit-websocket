local net = require('net')
local b64 = require('./base64.lua')
local sha1 = require('./sha1.lua')
local string = require('string')
local table = require('table')
local math = require('math')
local bit = require('bit')
require('./string.lua')(string)

function toBits(num)
    -- returns a table of bits, least significant first.
    local t={} -- will contain the bits
    while num>0 do
        rest=math.fmod(num,2)
        t[#t+1]=rest
        num=(num-rest)/2
    end
    return t
end

function decodeMessage(buf)
  local bytes = {}
  local byteString = ""
  for i = 1, #buf do
    bytes[i] = string.byte(buf:sub(i,i))
    byteString = byteString .. string.byte(buf:sub(i,i)) .. " "
  end

  local flags  = toBits(bytes[1])

  if flags[4] == 1 then
    return 1
  end
  if flags[1] == 0 then
    print("WebSocket Error: Message Fragmentation not supported.")
    return nil
  end
  bytes[1] = nil

  local length = 0
  local offset = 0

  if bytes[2]-128 >= 0 and bytes[2]-128 <= 125 then
    length = bytes[2] - 128
    bytes[2] = nil
    offset = 2
  elseif bytes[2] == 126 then
    length = tonumber(string.format("%x%x", bytes[3], bytes[4]), 16)
    bytes[2] = nil    bytes[3] = nil    bytes[4] = nil
    offset = 2 + 2
  elseif bytes[2] == 127 then
    length = tonumber(string.format("%x%x%x%x%x%x%x%x", bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10]), 16)
    bytes[2] = nil  bytes[3] = nil  bytes[4] = nil  bytes[5] = nil    bytes[6] = nil    bytes[7] = nil  bytes[8] = nil    bytes[9] = nil    bytes[10] = nil
    offset = 2 + 8
  end

  for k,v in pairs(bytes) do
    bytes[k-offset] = v
    bytes[k] = nil
  end

  local mask = {bytes[1], bytes[2], bytes[3], bytes[4]}
  bytes[1] = nil  bytes[2] = nil  bytes[3] = nil  bytes[4] = nil

  for k,v in pairs(bytes) do
    bytes[k-5] = v
    bytes[k] = nil
  end

  local ret = ""

  for i,v in pairs(bytes) do
    local b = bit.bxor(mask[(i % 4)+1], v)
    ret = ret .. string.char(b)
  end

  return ret
end



return function(port)

  local this = {}
  this.listener = {connect = {}, data = {}, disconnect = {}}

  this.on = function(this, s, c)
    if this.listener[s] and type(this.listener[s]) == "table" and type(c) == "function" then
      table.insert(this.listener[s], c)
    end
  end

  this.call = function(this, s, args)
    if this.listener[s] and type(this.listener[s]) == "table" then
      for k,v in pairs(this.listener[s]) do
        if type(v) == "function" then
          if type(args) == "table" then
            v(table.unpack(args))
          else
            v(args)
          end
        end
      end
    end
  end

  net.createServer(function (client)
    client:on("data", function(c)
      if c:sub(1, 3) == "GET" then
        local lines = c:split('\r\n')
        local title = lines[1]
        lines[1] = nil
        local data = {}

        for k,v in pairs(lines) do
          if #v > 2 then
            local line = v:split(": ")
            data[line[1]] = line[2]
          end
        end

        this:call("connect", client)

        local responseKey = data["Sec-WebSocket-Key"] .. '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'
        responseKey = b64.encode(sha1.binary(responseKey))
        local response = "HTTP/1.1 101 Switching Protocols\r\n"
                      .."Connection: Upgrade\r\n"
                      .."Upgrade: websocket\r\n"
                      .."Sec-WebSocket-Accept: " .. responseKey .. "\r\n"
                      .."\r\n"
        client:write(response, function() end)
      else
        local message = decodeMessage(c)
        if message == 1 then
          this:call("disconnect", client)
        elseif message then
          this:call("data", {client, message})
        else
          print("Could not parse message: " .. c)
        end
      end
    end)
  end):listen(port)

  print("WebSocket Server listening on port " .. port)

  return this
end
