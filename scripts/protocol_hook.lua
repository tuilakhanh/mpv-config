-- protocol_hook.lua
-- handlers.json: https://searchfox.org/mozilla-central/source/uriloader/exthandler/tests/unit/handlers.json
-- named pipe: mpv.exe --input-ipc-server=\\.\pipe\mpvsocket

local utils = require 'mp.utils'
local msg = require 'mp.msg'
local opts = require "mp.options"

local options = {
    cwd = '',
    ipcMode = false,
    proxy = '',
    nogeometry = true,
    stream_quality = '720p,best,worst',
}

opts.read_options(options, "protocol_hook")


-- MPV folder
local cwd = options.cwd
--Beta feature, Windows only (for now), true = on, false = off. check -- named pipe
local ipcMode = options.ipcMode
local proxy = options.proxy
print(proxy)
if proxy == '' then
    proxy = false
end
print(proxy)
local nogeometry = options.nogeometry
local stream_quality = options.stream_quality

print(cwd)

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

local function exedir()
    --local path1 = debug.getinfo(1).source
    local path = mp.command_native({'expand-path', '~~home/'})
    print(path)
    path = path:gsub('/portable_config.*', '')
    print(path)
    return path
end

local osv = getOS()
if cwd == '' then
    cwd = exedir()
    print(cwd)
end

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

local function regexEscape(str)
    return str:gsub("[%(%)%.%%%+%-%*%?%[%^%$%]]", "%%%1")
end
-- you can use return and set your own name if you do require() or dofile()

-- like this: str_replace = require("string-replace")
-- return function (str, this, that) -- modify the line below for the above to work
local function replace (str, this, that)
    return str:gsub(regexEscape(this), that:gsub("%%", "%%%%")) -- only % needs to be escaped for 'that'
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

local function stripqs(s)
    return string.gsub(s, '&.*', '')
end

local function escapeqs(s)
    return string.gsub(s, '&', '^&')
end

function magiclines(s)
        if s:sub(-1)~="\n" then s=s.."\n" end
        return s:gmatch("(.-)\n")
end

local function getDomain(url)
    return split(url, '/')[2]
end

local function livestreamer(url, referer, proxy, hls)
    print('Streamlink: '..url)
    local url2 = '"'..url..'"'
    local cmd = ''
    local cmd2 = url2..' '..stream_quality..' '
    --local cmdconfig = ''
    local cmdconfig = ' --config='..cwd..'/streamlink.conf'
    if osv == 'Windows' then
        cmd = 'run '..cwd..'/streamlink/bin/streamlink.exe '
    else
        cmd = 'run streamlink '
    end
    --if (url:find("hls://") == 1) then
    if (hls == true) then
        cmdconfig = cmdconfig..' --player-args=--demuxer-lavf-format=mpegts '
    end
    if proxy ~= false then
        cmd2 = cmd2..'--http-proxy='..proxy..'/'
    end
    print(referer)

    cmd = cmd..cmd2..cmdconfig
    if referer ~= '' then
        cmd = cmd..' --http-header=Referer='..referer
    end
    print(cmd)
    mp.command(cmd)
    --mp.command('quit')
end

-- Thank to pTalent: https://voz.vn/t/tong-hop-nhung-addon-chat-cho-firefox-pc-mobile.682181/post-27975348
local function iptv(url, referer, proxy, hls)
    print('IPTV: '..url)
    local url2 = '"'..url..'"'
    local playlist = false
    --if (url:find("hls://") == 1) then
    if (hls == true) then
        playlist = true
        --url = string.gsub(url, 'hls:', 'https:')
    end
    
    local curlpath = ''
    local mpvpath = ''
    local cmdcurl = ''
    local cmdmpv = ''
    local stdout = ''
    local stdfin = ''
    local domain = getDomain(url)
    print(domain)
    print(dump(split(url, '/')))
    if osv == 'Windows' then
        curlpath = cwd..'/curl.exe '
    else
        curlpath = 'curl '
    end
    if osv == 'Windows' then
        mpvpath = 'run '..cwd..'/mpv.exe '
    else
        mpvpath = 'mpv curl '
    end

	local args = {curlpath, url, "-L", '-s'}
    print(dump(args))
	local p = mp.command_native{
		name = "subprocess",
		capture_stdout = true,
		playback_only = false,
		args = args
	}
	if p.stdout then
        for line in magiclines(p.stdout) do
            if (line:find('/') == 1) then
                stdout = stdout..'https://'..domain..line..'\n'
            else
                stdout = stdout..line..'\n'
            end
        end
        --stdout = string.gsub(stdout, '/hls/', 'https://'..domain..'/hls/')
        print(stdout)
        f = io.open(cwd..'/dummy.m3u8', 'w')
        f:write(stdout)
        f:close()

        if playlist == true then
            mp.commandv('set', 'ytdl', 'no')
            mp.commandv('set', 'prefetch-playlist', 'yes')
            mp.commandv('set', 'demuxer-lavf-format', 'mpegts')
            mp.commandv('loadlist', cwd..'/dummy.m3u8')
        else
            mp.commandv('loadfile', cwd..'/dummy.m3u8')
        end
	end

    --cmdcurl = curlpath..' -L '..url2..' -o magicList.m3u8'
    --cmdmpv = mpvpath..' magicList.m3u8'
    --mp.command(cmdcurl)
    --mp.command(cmdmpv)
    --mp.commandv('loadfile', 'magicList.m3u8')
    --mp.command('quit')
end

local function mpv(url, referer, proxy, command)
    print('MPV: '..url)
    local url2 = '"'..url..'"'
    local cmd = ''
    if osv == 'Windows' then
        cmd = 'run '..cwd..'/mpv.exe '
    else
        cmd = 'run mpv '
    end
    if proxy ~= false then
        cmd = cmd..'--http-proxy='..proxy..'/'
    end
    if command then
        url2 = string.gsub(url2, '?geometry', '?geometry2')
        cmd = cmd..' '..command
    end
    cmd = cmd..' '..url2

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
    local cmd2 = ''
    if osv == 'Windows' then
        cmd = 'run cmd /c cd /d '..cwd..' && start yt-dlp.exe '
    else
        cmd = 'run yt-dlp '
    end
    if mode == 'audio' then
        cmd2 = ' -f ba --extract-audio '
    --else
    --    cmd2 = ' -f bv+ba/b '
    end
    cmd = cmd..cmd2..url2
    mp.command(cmd)
    --mp.command('quit')
end

local function exec2(args)
    local ret = utils.subprocess({args = args})
    return ret.status, ret.stdout, ret
end

local function gallery(url, referer)
    local es, urls, result = exec2({"gallery-dl", "-g", url})
    print(urls)
    if (es < 0) or (urls == nil) or (urls == "") then
        msg.error("failed to get album list.")
    end
    msg.info(urls)
    mp.commandv("loadlist", "memory://" .. urls)
end

local function ipc(url, mode)
    local cmd = 'run cmd /c echo loadfile '..url..' '..mode..' >\\\\.\\pipe\\mpvsocket'
    --print(cmd)
    mp.command(cmd)
end

local function piper(url, mode, proxy, hls)
    --yt-dlp -o - https://www.douyu.com/5092355 
    print(proxy)
    local url = escapeqs(url)
    local playlist = false
    --if (url:find("hls://") == 1) then
    if (hls == true) then
        playlist = true
        --url = string.gsub(url, 'hls:', 'https:')
    end
    local cmd = ''
    local audiourl = ''
    local audiocmd = ''
	local args = {'yt-dlp', '-f', 'ba', '-g', url}
    local quality = '-f bv[height^>=?1080][vcodec*=?avc1]'
    local mpvcmd =''
    local ytdlcmd = ''
    --print(dump(args))
    if string.find(url, 'youtube.com') then
        local p = mp.command_native{
            name = "subprocess",
            capture_stdout = true,
            playback_only = false,
            args = args
        }
        if p.stdout then
            audiourl = p.stdout
        end
        audiourl = escapeqs(audiourl)
        audiocmd = ' --audio-file='..audiourl
    else
        quality = ''
        audiocmd = ''
    end
    if audiocmd ~= '' then
        mpvcmd = mpvcmd..' '..audiocmd
    end
    if proxy ~= false then
        mpvcmd = mpvcmd..' '..'--http-proxy='..proxy
        ytdlcmd = ytdlcmd..' '..'--proxy='..proxy
    end
    if playlist ~= false then
        mpvcmd = mpvcmd..' '..'--demuxer-lavf-format=mpegts'
    end
    if quality ~= '' then
        ytdlcmd = ytdlcmd..' '..quality
    end
    if osv == 'Windows' then
        cmd = 'run cmd /c cd /d '..cwd..' && yt-dlp.exe '..ytdlcmd..' -o - '..url..' | mpv.exe -'..mpvcmd
    else
        cmd = 'run yt-dlp '..ytdlcmd..' -o - '..url..' | mpv -'..mpvcmd
    end
    print(cmd)
    print(cwd)
    mp.command(cmd)
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
print(dump(options))



if ipcMode == true then
    local ipc = mp.get_property("input-ipc-server", "")
    if ipc ~= "" then
        ipcMode = false
    end
end

local hook_count = 0

mp.add_hook("on_load", 1, function()
    local mode = 'append-play'
    local referer = ''
    local ourl = mp.get_property("stream-open-filename", "")
    local url = ourl
    local qs = {}
    local autopip = false
    local start = false
    local audio = false
    local playlist = false
    local pipe = false
    local hls = false
    if osv == 'MacOS' then
        url = 'mpv://'..url
    end
    if (url:find("mpv://") ~= 1) then
        print("not a mpv url: " .. url)
        return
    end
    --mp.set_property("stream-open-filename", "memory://")
    --mp.commandv('playlist-clear')
    --mp.commandv('playlist-remove', 'current')
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
            referer = qs['referer']
            referer = atobUrl(referer)
            print(referer)
        end
        if qs['autopip'] then
            autopip = true
            ourl = string.gsub(ourl, '?autopip=1', '')
        end
        if qs['hls'] then
            hls = true
        end
        if qs['start'] then
            start = qs['start']
        end
        if arr[2] == 'mpv69' then
            arr[2] = 'play'
            proxy = 'http://127.0.0.1:9966'
        end
        if arr[2] == 'ls69' then
            arr[2] = 'stream'
            proxy = 'http://127.0.0.1:9966'
        end
        if arr[2] == 'mpva' then
            arr[2] = 'play'
            audio = true
        end
        if arr[2] == 'mpvp' or arr[2] == 'list' then
            arr[2] = 'play'
            mp.commandv('set', 'ytdl', 'no')
            playlist = true
        end
        if arr[2] == 'mpvi' then
            arr[2] = 'play'
            autopip = true
        end
        if arr[2] == 'mpvy' then
            arr[2] = 'play'
            pipe = true
        end
        if arr[2] == 'ytdla' then
            arr[2] = 'ytdl'
            audio = true
        end
        if referer ~= '' then
            mp.commandv('set', 'http-header-fields', 'Referer: '..referer)
        end
        if proxy ~= false then
            local ytdlrawoptions = mp.get_property_native('ytdl-raw-options', '')
            --print(dump(ytdlrawoptions))
            ytdlrawoptions['proxy'] = proxy
            --mp.commandv('set', 'http-proxy', proxy..'/')
            --mp.commandv('set', 'ytdl-raw-options', 'proxy='..proxy..','..ytdlrawoptions)
            mp.set_property('http-proxy', proxy..'/')
            --mp.set_property('ytdl-raw-options', 'proxy='..proxy..','..ytdlrawoptions)
            mp.set_property_native('ytdl-raw-options', ytdlrawoptions)
            --local ytdlrawoptions = mp.get_property_native('ytdl-raw-options', '')
            --print(dump(ytdlrawoptions))
        end
        if arr[2] == 'play' then
            --local pp = mp.get_property('playlist-pos')
            --mp.commandv('playlist-remove', pp)
            if audio == true then
                mp.commandv('set', 'video', 'no')
            end
            if start ~= false then
                mp.commandv('set', 'start', start)
            end
            if ipcMode == false then
                if pipe == true then
                    piper(url, false, proxy, hls)
                    return
                end
                if qs['geometry'] and nogeometry == false then
                    mpv(ourl, referer, proxy, '--geometry='..qs['geometry'])
                    return
                end
                if autopip == true then
                    ipc(ourl, 'replace')
                else
                    for link in string.gmatch(url, "[^%s]+") do

                        
                        if hook_count > 0 then
                            mode = 'replace'
                        end
                        if playlist == false then
                            mp.commandv('loadfile', link, mode)
                        else
                            --mp.commandv('loadlist', link, mode)
                            iptv(url, referer, proxy, hls)
                        end
                        if hook_count > 0 then
                            mp.commandv('loadfile', ourl, 'append')
                        end
                    end
                end
            else
                ipc(ourl, 'append-play')
            end
        elseif arr[2] == 'stream' then
            for link in string.gmatch(url, "[^%s]+") do
                livestreamer(link, referer, proxy, hls)
            end
            --livestreamer(url, referer)
        elseif arr[2] == 'ytdl' then
            for link in string.gmatch(url, "[^%s]+") do
                if audio == false then
                    ytdl(link, referer, 'video')
                else
                    ytdl(link, referer, 'audio')
                end
            end
            --ytdl(url, referer, 'video')
        elseif arr[2] == 'mg' then
            for link in string.gmatch(url, "[^%s]+") do
                gallery(link, referer)
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
        hook_count = hook_count + 1
    end
end)

