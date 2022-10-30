local class = require('jls.lang.class')
local system = require('jls.lang.system')
local Promise = require('jls.lang.Promise')
local StringBuffer = require('jls.lang.StringBuffer')
local File = require('jls.io.File')
local strings = require('jls.util.strings')
local TableList = require('jls.util.TableList')
local LocalDateTime = require('jls.util.LocalDateTime')

local function getExecutableName(name)
  if system.isWindows() then
    return name..'.exe'
  end
  return name
end

local function hash(value)
  return math.abs(strings.hash(value))
end

local function computeFileId(file)
  return ''
  ..strings.formatInteger(hash(file:getName()), 64)
  --..strings.formatInteger(hash(file:getParent()), 64)
  ..strings.formatInteger(file:lastModified(), 64)
  ..strings.formatInteger(file:length(), 64)
end


return class.create(function(ffmpeg)

  function ffmpeg:initialize(cacheDir)
    self.cacheDir = cacheDir
    self.sources = {}
  end

  function ffmpeg:configure(options)
    local ffDir = File:new(options.ffmpeg)
    if ffDir:isDirectory() then
      self.ffmpegPath = File:new(ffDir, getExecutableName('ffmpeg')):getPath()
    else
      self.ffmpegPath = ffDir:getPath()
      ffDir = ffDir:getParentFile()
    end
    if options.ffprobe then
      self.ffprobePath = options.ffprobe
    else
      if ffDir then
        self.ffprobePath = File:new(ffDir, getExecutableName('ffprobe')):getPath()
      else
        self.ffprobePath = getExecutableName('ffprobe')
      end
    end
  end

  function ffmpeg:check()
    local ffmpegFile = File:new(self.ffmpegPath)
    if not ffmpegFile:exists() then
      return nil, 'ffmpeg not found, '..ffmpegFile:getPath()
    end
    local ffprobeFile = File:new(self.ffprobePath)
    if not ffprobeFile:exists() then
      return nil, 'ffprobe not found, '..ffprobeFile:getPath()
    end
    return true
  end

  local function formatTime(v, showMs)
    local h, m, s, ms
    ms = math.floor(v * 1000) % 1000
    v = math.floor(v)
    h = v // 3600
    m = (v % 3600) // 60
    s = v % 60
    if showMs or (ms > 0) then
      return string.format('%02d:%02d:%02d.%03d', h, m, s, ms)
    end
    return string.format('%02d:%02d:%02d', h, m, s)
  end

  local function parseTime(v)
    local h, m, s, ms = string.match(v, '^(%d+):(%d+):(%d+).?(%d*)$')
    h = tonumber(h)
    m = tonumber(m)
    s = tonumber(s)
    ms = tonumber('0.'..ms)
    if ms == 0 then
      ms = 0
    end
    return (h * 60 + m) * 60 + s + ms
  end

  function ffmpeg:computeArguments(destFilename, destOptions, srcFilename, srcOptions, globalOptions)
    local args = {self.ffmpegPath, '-hide_banner'}
    if globalOptions then
      TableList.concat(args, globalOptions)
    end
    if srcOptions then
      TableList.concat(args, srcOptions)
    end
    if srcFilename then
      TableList.concat(args, '-i', srcFilename)
    end
    if destOptions then
      TableList.concat(args, destOptions)
    end
    if destFilename then
      TableList.concat(args, '-y', destFilename)
    end
    return args
  end

  function ffmpeg:createCommand(part, filename, options, seekDelay)
    --[[
      '-ss position (input/output)'
      When used as an input option (before -i), seeks in this input file to position.
      When used as an output option (before an output filename), decodes but discards input until the timestamps reach position.
      This is slower, but more accurate. position may be either in seconds or in hh:mm:ss[.xxx] form.

      Seek delay in milli seconds
      When positive, it is used for combined seeking.
      Default value -1 means input seeking and as of FFmpeg 2.1 is a now also "frame-accurate".
      Value -2 means output seeking which is very slow.
      See https://trac.ffmpeg.org/wiki/Seeking

      '-to position (output)'
      Stop writing the output at position. position may be a number in seconds, or in hh:mm:ss[.xxx] form.
      -to and -t are mutually exclusive and -t has priority.
      '-vframes number (output)'
      Set the number of video frames to record. This is an alias for -frames:v.
    ]]
    local srcOptions = {}
    local destOptions = {}
    if part.from ~= nil then
      local delay = seekDelay or 0
      if (delay >= 0) and (delay < part.from) then
        TableList.concat(srcOptions, '-ss', formatTime(part.from - delay))
        TableList.concat(destOptions, '-ss', math.floor(delay))
      elseif delay == -1 then
        TableList.concat(srcOptions, '-ss', formatTime(part.from))
      else
        TableList.concat(destOptions, '-ss', formatTime(part.from))
      end
    end
    if part.to ~= nil then
      if part.from ~= nil then
        TableList.concat(destOptions, '-t', formatTime(part.to - part.from))
        --TableList.concat(destOptions, '-to', formatTime(part.to))
      else
        TableList.concat(destOptions, '-t', formatTime(part.to))
      end
    end
    TableList.concat(destOptions, options)
    local sourceFile = self.sources[part.sourceId]
    return self:computeArguments(filename, destOptions, sourceFile:getPath(), srcOptions)
  end

  function ffmpeg:createTempFile(filename)
    return File:new(self.cacheDir, filename)
  end

  function ffmpeg:createCommands(filename, parts, destOptions, seekDelayMs)
    local commands = {}
    if #parts == 1 then
      table.insert(commands, self:createCommand(parts[1], filename, destOptions, seekDelayMs))
    elseif #parts > 1 then
      local concatScript = StringBuffer:new()
      concatScript:append('# fcut')
      for i, part in ipairs(parts) do
        local partName = 'part_'..tostring(i)..'.tmp'
        local outFilename = self:createTempFile(partName):getPath()
        table.insert(commands, self:createCommand(part, outFilename, destOptions, seekDelayMs))
        local concatPartname = string.gsub(outFilename, '[\\+]', '/')
        --local concatPartname = partName -- to be safe
        concatScript:append('\nfile ', concatPartname)
      end
      local concatFile = self:createTempFile('concat.txt');
      concatFile:write(concatScript:toString());
      table.insert(commands, self:computeArguments(filename, {'-c', 'copy'}, concatFile:getPath(), {'-f', 'concat', '-safe', '0'}))
    end
    return commands
  end

  function ffmpeg:openSource(filename)
    return Promise:new(function(resolve, reject)
      local file = File:new(filename)
      if not file:isFile() then
        reject('File not found')
        return
      end
      local id = computeFileId(file)
      self.sources[id] = file
      local sourceCache = File:new(self.cacheDir, id)
      if not sourceCache:isDirectory() then
        if not sourceCache:mkdir() then
          reject('Unable to create cache directory')
          return
        end
      end
      resolve(id)
    end)
  end

  function ffmpeg:createProbeCommand(id)
    local sourceFile = self.sources[id]
    if not sourceFile then
      Promise.reject('Unknown source id "'..id..'"');
    end
    return {self.ffprobePath, '-hide_banner', '-v', '0', '-show_format', '-show_streams', '-of', 'json', sourceFile:getPath()}
  end

  function ffmpeg:createPreviewAtCommand(id, sec, file, width, height)
    local sourceFile = self.sources[id]
    if not sourceFile then
      Promise.reject('Unknown source id "'..id..'"');
    end
    local time = LocalDateTime:new():plusSeconds(sec or 0):toTimeString()
    local args = {self.ffmpegPath, '-hide_banner', '-v', '0', '-ss', time, '-i', sourceFile:getPath(), '-f', 'mjpeg', '-vcodec', 'mjpeg', '-vframes', '1', '-an'}
    if width and height then
      TableList.concat(args, '-s', tostring(width)..'x'..tostring(height))
    end
    TableList.concat(args, '-y', file:getPath())
    return args
  end

end)
