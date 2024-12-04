-- optionally import module, from SO
local function want(name)
  local out; if xpcall(
      function()  out = require(name) end,
      function(e) out = e end)
  then return out          -- success                                     
  else return nil, out end -- error                                       
end

local utils = require('mp.utils')
local input = require('mp.input')
local mp = require('mp')
local http = want("socket.http")
local https = want("ssl.https")

local options = {
    source_lang = "fr",
    load_autosub_binding = "alt+y",
    autoload_autosub_binding = "alt+Y",
    cache_dir = utils.join_path(os.getenv("HOME"), ".cache/ytsub/"),
}
require("mp.options").read_options(options)

-- create cache directory for subtitles if it doesn't exist
local res = utils.file_info(options.cache_dir)
if not res or not res.is_dir then
    mp.command_native({
        name = "subprocess",
        args = {"mkdir", options.cache_dir},
        playback_only = false,
    })
end

local function info(msg)
    mp.osd_message('ytsub : ' .. msg, 5)
end

local function load_autosub(lang, sub_info, ytid, is_primary)
    local lang_name
    local url
    for _,v in pairs(sub_info) do
        lang_name = v["name"]
        if v["ext"] == "vtt" then
            url = v["url"]
        end
    end

    info('loading '..lang_name)

    local subfile_base = utils.join_path(options.cache_dir, ytid) -- for yt-dlp
    local subfile = subfile_base .. "." .. lang .. ".vtt"

    local f = io.open(subfile, "r")
    local sub_is_available = false
    if f ~= nil then
        -- sub file already present
        io.close(f)
        sub_is_available = true
    else
        -- sub file not already present, download
        if http ~= nil and https ~= nil then
            -- downloading via direct url
            local body, _ = http.request(url)
            if body ~= nil then
                f = assert(io.open(subfile, 'wb'))
                f:write(body)
                f:close()
                sub_is_available = true
            end
        else
            -- lua http modules not available, download via yt-dlp
            local ytdl_path = mp.get_property_native('user-data/mpv/ytdl/path')
            if ytdl_path ~= nil then
                mp.command_native({
                    name = "subprocess",
                    args = {ytdl_path, "--skip-download", "--sub-lang", lang, "--write-auto-sub", "-o", subfile_base, ytid}
                })
                f = io.open(subfile, "r")
                if f ~= nil then
                    io.close(f)
                    sub_is_available = true
                end
            end
        end
    end

    -- load the subtitle file as track ans select it
    if sub_is_available then
        if is_primary then
            mp.command("sub-add " .. subfile .. " select 'youtube auto-sub' '" .. lang .. "'")
        else
            -- compute the number of subtitle tracks in order to select the new track by id
            local n_tracks = mp.get_property_native("track-list/count")
            local n_subs = 0
            local i = 0
            while i < n_tracks do
                if mp.get_property_native("track-list/"..i.."/type") == "sub" then
                    n_subs = n_subs + 1
                end
                i = i + 1
            end
            mp.command("sub-add " .. subfile .. " auto 'youtube auto-sub' '" .. lang .. "'")
            mp.set_property("secondary-sid", n_subs + 1)
        end
        info(lang_name .. ' loaded')
    else
        info('failed to download ' .. lang_name)
    end
end

local function ytsub(is_auto)
    local ytdl_output = mp.get_property_native('user-data/mpv/ytdl/json-subprocess-result')
    if ytdl_output == nil then
        info('no ytdl info available')
        return
    end

    local j = utils.parse_json(ytdl_output['stdout'])
    local subs = j['automatic_captions']
    if subs == nil then
        info('no auto-subs found')
        return
    end

    if is_auto then
        -- load the original language as primary subtitle and
        -- the source language as secondary subtitle
        local source_lang = options.source_lang

        local orig_lang
        for k,_ in pairs(subs) do
            if string.find(k, "(orig)") ~= nil then
                orig_lang = k
                break
            end
        end

        load_autosub(orig_lang, subs[orig_lang], j["id"], true)
        if orig_lang == source_lang.."-orig" then
            info("source language and original language are the same ("..source_lang..")")
        else
            load_autosub(source_lang, subs[source_lang], j["id"], false)
        end

    else
        -- let the user select the language to load interactively
        local langs = {}
        for k,_ in pairs(subs) do
            table.insert(langs, k)
        end

        input.select({
            prompt = "Select a language",
            items = langs,
            submit = function(lang_id) load_autosub(langs[lang_id], subs[langs[lang_id]], j["id"], true) end,
        })
    end
end

mp.add_key_binding(options.load_autosub_binding, "load", function() ytsub(false) end)
mp.add_key_binding(options.autoload_autosub_binding, "auto", function() ytsub(true) end)
