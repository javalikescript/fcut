os.setlocale('') -- set native locale

local system = require('jls.lang.system')
local runtime = require('jls.lang.runtime')
local Promise = require('jls.lang.Promise')
local logger = require('jls.lang.logger')
local event = require('jls.lang.event')
local File = require('jls.io.File')
local tables = require('jls.util.tables')
local Map = require('jls.util.Map')
local WebView = require('jls.util.WebView')
local FileHttpHandler = require('jls.net.http.handler.FileHttpHandler')
local RestHttpHandler = require('jls.net.http.handler.RestHttpHandler')
local ZipFileHttpHandler = require('jls.net.http.handler.ZipFileHttpHandler')
local TableHttpHandler = require('jls.net.http.handler.TableHttpHandler')
local WebSocketUpgradeHandler = require('jls.net.http.ws').WebSocketUpgradeHandler

local FileChooser = require('FileChooser')
local Ffmpeg = require('Ffmpeg')
local ExecWorker = require('ExecWorker')

local function processFile(file, processFn)
  if file:exists() then
    return Promise.resolve()
  end
  local tmpFile = File:new(file:getParentFile(), file:getName()..'.tmp')
  return processFn(tmpFile):next(function()
    tmpFile:renameTo(file)
  end, function(reason)
    tmpFile:delete()
    return Promise.reject(reason)
  end)
end

local CONFIG_SCHEMA = {
  title = 'Fast Cut',
  type = 'object',
  additionalProperties = false,
  properties = {
    config = {
      title = 'The configuration file',
      type = 'string',
      default = 'fcut.json',
    },
    cache = {
      title = 'The cache path, relative to the user home',
      type = 'string',
      default = './.fcut_cache',
    },
    media = {
      title = 'The media path, relative to the work directory',
      type = 'string',
      default = '.',
    },
    project = {
      title = 'A project file to load',
      type = 'string',
    },
    ffmpeg = {
      title = 'The ffmpeg path',
      type = 'string',
      default = (system.isWindows() and 'ffmpeg\\ffmpeg.exe' or '/usr/bin/ffmpeg'),
    },
    ffprobe = {
      title = 'The ffprobe path',
      type = 'string',
    },
    webview = {
      type = 'object',
      additionalProperties = false,
      properties = {
        debug = {
          title = 'Enable WebView debug mode',
          type = 'boolean',
          default = false,
        },
        ie = {
          title = 'Disable WebView2 (Edge)',
          type = 'boolean',
          default = false,
        },
        port = {
          title = 'WebView HTTP server port',
          type = 'integer',
          default = 0,
          minimum = 0,
          maximum = 65535,
        },
      }
    },
  },
}

local config = tables.createArgumentTable(arg, {
  helpPath = 'help',
  configPath = 'config',
  emptyPath = 'config',
  schema = CONFIG_SCHEMA
});

local execWorker = ExecWorker:new()
local ffmpeg = Ffmpeg:new(config, execWorker)

local cacheDir = ffmpeg:getCacheDir()
logger:info('Cache directory is '..cacheDir:getPath())

local scriptFile = File:new(arg[0]):getAbsoluteFile()
local scriptDir = scriptFile:getParentFile()

local webSocket
local function webSocketSend(line)
  if webSocket and line then
    webSocket:sendTextMessage(line)
  end
end

if config.webview.ie then
  system.setenv('WEBVIEW2_WIN32_PATH', 'na')
end

local assetsHandler
local assetsDir = File:new(scriptDir, 'assets')
local assetsZip = File:new(scriptDir, 'assets.zip')
if assetsDir:isDirectory() then
  assetsHandler = FileHttpHandler:new(assetsDir)
elseif assetsZip:isFile() then
  assetsHandler = ZipFileHttpHandler:new(assetsZip)
end

WebView.open('http://localhost:'..tostring(config.webview.port)..'/', {
  title = 'Fast Cut (Preview)',
  resizable = true,
  bind = true,
  debug = config.webview.debug,
}):next(function(webview)
  local httpServer = webview:getHttpServer()
  logger:info('WebView opened with HTTP Server bound on port '..tostring(select(2, httpServer:getAddress())))
  httpServer:createContext('/(.*)', FileHttpHandler:new(File:new(scriptDir, 'htdocs'), nil, 'fcut.html'))
  httpServer:createContext('/config/(.*)', TableHttpHandler:new(config, nil, true))
  httpServer:createContext('/assets/(.*)', assetsHandler)
  httpServer:createContext('/source/([^/]+)/(%d+)%.jpg', Map.assign(FileHttpHandler:new(cacheDir), {
    getPath = function(_, exchange)
      return string.sub(exchange:getRequest():getTargetPath(), 9)
    end,
    prepareFile = function(_, exchange, file)
      local id, sec = exchange:getRequestArguments()
      return processFile(file, function(tmpFile)
        return ffmpeg:extractPreviewAt(id, tonumber(sec), tmpFile)
      end)
    end
  }))
  httpServer:createContext('/source/([^/]+)/info%.json', Map.assign(FileHttpHandler:new(cacheDir), {
    getPath = function(_, exchange)
      return string.sub(exchange:getRequest():getTargetPath(), 9)
    end,
    prepareFile = function(_, exchange, file)
      local id = exchange:getRequestArguments()
      return processFile(file, function(tmpFile)
        return ffmpeg:extractInfo(id, tmpFile)
      end)
    end
  }))
  httpServer:createContext('/rest/(.*)', RestHttpHandler:new({
    ['getSourceId?method=POST'] = function(exchange)
      local filename = exchange:getRequest():getBody()
      return ffmpeg:openSource(filename)
    end,
    ['listFiles?method=POST'] = function(exchange)
      local path = exchange:getRequest():getBody()
      local promise, callback = Promise.createWithCallback()
      FileChooser.listFiles(path, callback)
      return promise
    end,
    ['writeFile(requestJson)?method=POST&Content-Type=application/json'] = function(exchange, obj)
      local f = File:new(obj.path)
      f:write(obj.data)
      return 'saved'
    end,
    ['readFile(requestJson)?method=POST'] = function(exchange)
      local path = exchange:getRequest():getBody()
      local f = File:new(path)
      return f:readAll()
    end,
    ['fullscreen(requestJson)?method=POST&Content-Type=application/json'] = function(exchange, fullscreen)
      webview:fullscreen(fullscreen == true);
    end,
    ['export(requestJson)?method=POST&Content-Type=application/json'] = function(exchange, parameters)
      local commands = ffmpeg:createCommands(parameters.filename, parameters.parts, parameters.options or {}, parameters.seekDelayMs)
      logger:info(tostring(#commands)..' command(s)')
      local function executeNextCommand()
        local command = table.remove(commands, 1)
        if command then
          local line = runtime.formatCommandLine(command.line)
          logger:info('execute: '..tostring(line))
          return execWorker:execute(line, nil, webSocketSend, 'error'):next(function()
            logger:info('execute done, '..tostring(#commands)..' command(s)')
            return executeNextCommand()
          end)
        end
        return Promise.resolve();
      end
      return executeNextCommand():next(function()
        logger:info('export completed')
      end, function()
        logger:info('export failed')
      end)
    end,
  }))
  httpServer:createContext('/console/', Map.assign(WebSocketUpgradeHandler:new(), {
    onOpen = function(_, newWebSocket)
      if webSocket then
        webSocket:close()
      end
      webSocket = newWebSocket
    end
  }))
  return webview:getThread():ended()
end):next(function()
  logger:info('WebView closed')
end):catch(function(err)
  logger:info('Cannot open webview due to '..tostring(err))
end):next(function()
  execWorker:close()
  if webSocket then
    webSocket:close()
  end
end)

event:loop()
