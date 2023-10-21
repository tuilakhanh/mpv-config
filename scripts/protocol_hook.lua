-- protocol_hook.lua
-- handlers.json: https://searchfox.org/mozilla-central/source/uriloader/exthandler/tests/unit/handlers.json
-- named pipe: mpv.exe --input-ipc-server=\\.\pipe\mpvsocket

local utils = require 'mp.utils'
local msg = require 'mp.msg'
-- MPV folder
local cwd = ''
--Beta feature, Windows only (for now), true = on, false = off. check -- named pipe
local ipcMode = false

--[[function getOS(cmd, raw)
  local f = assert(io.popen(cmd, 'r'))
  local s = assert(f:read('*a'))
  f:close()
  if raw then return s end
  s = string.gsub(s, '^%s+', '')
  s = string.gsub(s, '%s+$', '')
  s = string.gsub(s, '[\n\r]+', ' ')
  return s
end

function getOS()
	-- ask LuaJIT first
	if jit then
		return jit.os
	end

	-- Unix, Linux variants
	local fh,err = assert(io.popen("uname -o 2>/dev/null","r"))
	if fh then
		osname = fh:read()
	end

	return osname or "Windows"
end

print(getOS())]]--

local function getOS()
    local BinaryFormat = package.cpath
    --print(BinaryFormat)
    if BinaryFormat:match("dll$") then
        return "Windows"
    elseif BinaryFormat:match("so$") then
        if BinaryFormat:match("homebrew") then
            return "MacOS"
        else
            return "Linux"
        end
    elseif BinaryFormat:match("dylib$") then
        return "MacOS"
    end
end

--print(getOS())

local function parseqs(url)
    -- return 0-based index to use with --playlist-start

    local query = url:match("%?.+")
    if not query then return nil end

    local args = {}
    for arg, param in query:gmatch("(%a+)=([^&?]+)") do
        if arg and param then
            args[arg] = param
        end
    end
    return args
end

local function dump(o)
   if type(o) == 'table' then
      local s = '{ '
      for k,v in pairs(o) do
         if type(k) ~= 'number' then k = '"'..k..'"' end
         s = s .. '['..k..'] = ' .. dump(v) .. ','
      end
      return s .. '} '
   else
      return tostring(o)
   end
end

local function split(text, delim)
    -- returns an array of fields based on text and delimiter (one character only)
    local result = {}
    local magic = "().%+-*?[]^$"

    if delim == nil then
        delim = "%s"
    elseif string.find(delim, magic, 1, true) then
        -- escape magic
        delim = "%"..delim
    end

    local pattern = "[^"..delim.."]+"
    for w in string.gmatch(text, pattern) do
        table.insert(result, w)
    end
    return result
end

local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/' -- You will need this for encoding/decoding
-- encoding
local function enc(data)
    return ((data:gsub('.', function(x) 
        local r,b='',x:byte()
        for i=8,1,-1 do r=r..(b%2^i-b%2^(i-1)>0 and '1' or '0') end
        return r;
    end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if (#x < 6) then return '' end
        local c=0
        for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
        return b:sub(c+1,c+1)
    end)..({ '', '==', '=' })[#data%3+1])
end

-- decoding
local function dec(data)
    data = string.gsub(data, '[^'..b..'=]', '')
    return (data:gsub('.', function(x)
        if (x == '=') then return '' end
        local r,f='',(b:find(x)-1)
        for i=6,1,-1 do r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0') end
        return r;
    end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if (#x ~= 8) then return '' end
        local c=0
        for i=1,8 do c=c+(x:sub(i,i)=='1' and 2^(8-i) or 0) end
            return string.char(c)
    end))
end

local function atobUrl(url)
    url = string.gsub(url, '_', '/')
    url = string.gsub(url, '-', '+')
    url = dec(url)
    return url
end

local function exec(args)
    print("Running: " .. table.concat(args, " "))

    return mp.command_native({
        name = "subprocess",
        args = args,
        capture_stdout = true,
        capture_stderr = true,
    })
end

local function livestreamer(url, referer)
    print('Streamlink: '..url)
    local url2 = '"'..url..'"'
    local cmd = ''
    if getOS() == 'Windows' then
        cmd = 'run '..cwd..'/streamlink/bin/streamlink.exe '..url2..' 720p,best,worst --config='..cwd..'/streamlink.conf'
    else
        cmd = 'run streamlink '..url2..' 720p,best,worst --config='..cwd..'/streamlink.conf'
    end
    --print(cmd)
    mp.command(cmd)
    --mp.command('quit')
end

local function EA(url, referer, app)
    print('EA: '..url)
    local url2 = '"'..url..'"'
    local cmd = 'run '..app..' '..url2
    mp.command(cmd)
    --mp.command('quit')
end

local function ytdl(url, referer, mode)
    print('YTDL: '..url)
    local url2 = '"'..url..'"'
    local cmd = ''
    if mode == 'audio' then
        if getOS() == 'Windows' then
            cmd = 'run cmd /c cd /d '..cwd..' && start yt-dlp -f ba --extract-audio '..url2
        else
            cmd = 'run yt-dlp -f ba --extract-audio '..url2
        end
    else
        if getOS() == 'Windows' then
            cmd = 'run cmd /c cd /d '..cwd..' && start yt-dlp '..url2
        else
            cmd = 'run yt-dlp '..url2
        end
    end
    mp.command(cmd)
    --mp.command('quit')
end

local function piper(url)
    local cmd = 'run cmd /c echo loadfile '..url..' append-play >\\\\.\\pipe\\mpvsocket'
    --print(cmd)
    mp.command(cmd)
end

local function exedir()
    --local path1 = debug.getinfo(1).source
    local path = mp.find_config_file('.')
    if path:match('portable_config') then
        return path:gsub('/portable_config/.*', '')
    end


end

--print(dump(mp))
--print(mp.find_config_file('.'))
--print(utils.join_path(mp.find_config_file('.'),"streamlink"))
--print(dump(debug.getinfo(1)))
--print(debug.getinfo(1).source)
--current_dir=io.popen"cd":read'*l'
--print(current_dir)
--print(package.path)
--print(package.cpath)
--print(os.getenv('PATH'))

if cwd == '' then
    cwd = exedir()
    print(cwd)
end

if ipcMode == true then
    local ipc = mp.get_property("input-ipc-server", "")
    if ipc ~= "" then
        ipcMode = false
    end
end

mp.add_hook("on_load", 15, function()
    local referer = ''
    local ourl = mp.get_property("stream-open-filename", "")
    local url = ourl
    local qs = {}
    if getOS() == 'MacOS' then
        url = 'mpv://'..url
    end
    if (url:find("mpv://") ~= 1) then
        print("not a mpv url: " .. url)
        return
    end
    local arr = split(url, '/')
    if arr[1] == 'mpv:' then
        url = atobUrl(arr[3])
        if (url:find("data:") == 1) then
            url = atobUrl(split(url, ',')[2])
            --print(url)
        end
        if arr[4] then
            qs = parseqs(arr[4])
        end
        local function subadd()
            local subs = qs['subs']
            subs = atobUrl(subs)
            mp.commandv('sub-add', subs)
        end
        local function cleanup()
            mp.commandv("playlist-remove", "0")
        end
        --mp.register_event("file-loaded", cleanup)
        if qs['subs'] then
            mp.register_event("file-loaded", subadd)
        end
        if qs['referer'] then
            local referer = qs['referer']
            referer = atobUrl(referer)
        end
        if arr[2] == 'play' then
            if ipcMode == false then
                for link in string.gmatch(url, "[^%s]+") do
                    if referer ~= '' then
                        mp.commandv('set', 'http-header-fields', 'Referer: "'..referer..'"')
                    end
                    mp.commandv('loadfile', link, 'append')
                end
            else
                piper(ourl)
            end
        elseif arr[2] == 'list' then
            if ipcMode == false then
                for link in string.gmatch(url, "[^%s]+") do
                    if referer ~= '' then
                        mp.commandv('set', 'http-header-fields', 'Referer: "'..referer..'"')
                    end
                    mp.commandv('loadlist', link, 'append')
                end
            else
                piper(ourl)
            end
        elseif arr[2] == 'mg' then
            mp.set_property('osd-duration', '0')
            for link in string.gmatch(url, "[^%s]+") do
                link = 'gallery-dl://'..link
                mp.commandv('loadfile', link, 'append')
            end
        --[[elseif arr[2] == 'mpv69' then
            --mp.commandv('set', 'http-proxy', 'http://127.0.0.1:9966/')
            mp.set_property('http-proxy', 'http://127.0.0.1:9966/')
            --mp.commandv('set', 'ytdl-raw-options-append', 'proxy=http://127.0.0.1:9966')
            mp.set_property('ytdl-raw-options-append', 'proxy=http://127.0.0.1:9966')
            for link in string.gmatch(url, "[^%s]+") do
                if referer ~= '' then
                    mp.commandv('set', 'http-header-fields', 'Referer: "'..referer..'"')
                end
                mp.commandv('loadfile', link, 'append')
            end]]--
        elseif arr[2] == 'stream' then
            for link in string.gmatch(url, "[^%s]+") do
                livestreamer(link, referer)
            end
            --livestreamer(url, referer)
        elseif arr[2] == 'ytdl' then
            for link in string.gmatch(url, "[^%s]+") do
                ytdl(link, referer, 'video')
            end
            --ytdl(url, referer, 'video')
        elseif arr[2] == 'ytdla' then
            for link in string.gmatch(url, "[^%s]+") do
                ytdl(link, referer, 'audio')
            end
            --ytdl(url, referer, 'audio')
        elseif qs['app'] then
            for link in string.gmatch(url, "[^%s]+") do
                local app = qs['app']
                app = atobUrl(app)
                EA(link, referer, app)
            end
            --local app = qs['app']
            --app = atobUrl(app)
            --EA(url, referer, app)
        end
        
    end
end)

