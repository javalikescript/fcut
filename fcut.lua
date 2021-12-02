os.setlocale('') -- set native locale

local system = require('jls.lang.system')
local runtime = require('jls.lang.runtime')
local Promise = require('jls.lang.Promise')
local logger = require('jls.lang.logger')
local event = require('jls.lang.event')
local ProcessBuilder = require('jls.lang.ProcessBuilder')
local Pipe = require('jls.io.Pipe')
local File = require('jls.io.File')
local tables = require('jls.util.tables')
local strings = require('jls.util.strings')
local Map = require('jls.util.Map')
local HttpExchange = require('jls.net.http.HttpExchange')
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
    loglevel = {
      title = 'The log level',
      type = 'string',
      default = 'WARN',
      enum = {'ERROR', 'WARN', 'INFO', 'CONFIG', 'FINE', 'FINER', 'FINEST', 'DEBUG', 'ALL'},
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
        disable = {
          title = 'Disable WebView',
          type = 'boolean',
          default = false,
        },
        ie = {
          title = 'Enable IE',
          type = 'boolean',
          default = false,
        },
        address = {
          title = 'The binding address',
          type = 'string',
          default = '::'
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

logger:setLevel(config.loglevel)

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

local exportContexts = {}

local function createHttpContexts(httpServer)
  logger:info('HTTP Server bound on port '..tostring(select(2, httpServer:getAddress())))
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
    ['getFile?method=POST'] = function(exchange)
      local path = exchange:getRequest():getBody()
      local file = File:new(path)
      if not file:exists() then
        HttpExchange.notFound(exchange, 'File not found')
        return false
      end
      return {
        name = file:getName(),
        isDirectory = file:isDirectory(),
        length = file:length(),
        lastModified = file:lastModified(),
      }
    end,
    ['writeFile(requestJson)?method=POST&Content-Type=application/json'] = function(exchange, obj)
      local f = File:new(obj.path)
      if not obj.overwrite and f:exists() then
        HttpExchange.forbidden(exchange, 'The file exists')
        return false
      end
      f:write(obj.data)
      return 'saved'
    end,
    ['readFile(requestJson)?method=POST'] = function(exchange)
      local path = exchange:getRequest():getBody()
      local f = File:new(path)
      return f:readAll()
    end,
    ['cancelExport?method=POST'] = function(exchange)
      local exportId = exchange:getRequest():getBody()
      local exportContext = exportContexts[exportId]
      if exportContext and exportContext.process then
        exportContext.process:destroy()
        exportContexts[exportId] = nil
      end
    end,
    ['export(requestJson)?method=POST&Content-Type=application/json'] = function(exchange, parameters)
      local commands = ffmpeg:createCommands(parameters.filename, parameters.parts, parameters.options or {}, parameters.seekDelayMs)
      local exportId = strings.formatInteger(system.currentTimeMillis(), 64)
      logger:info('export '..exportId..' '..tostring(#commands)..' command(s)')
      exportContexts[exportId] = {
        commands = commands,
      }
      return exportId
    end,
  }))
  httpServer:createContext('/console/(.*)', Map.assign(WebSocketUpgradeHandler:new(), {
    onOpen = function(_, webSocket, exchange)
      local exportId = exchange:getRequestArguments()
      local exportContext = exportContexts[exportId]
      if not exportContext then
        webSocket:close()
        return
      end
      exportContext.index = 0
      local function endExport(exitCode)
        exportContext.exitCode = exitCode
        webSocket:close()
        exportContexts[exportId] = nil
      end
      local function startNextCommand()
        exportContext.index = exportContext.index + 1
        if exportContext.index > #exportContext.commands then
          endExport(0)
          return
        end
        local command = exportContext.commands[exportContext.index]
        local pb = ProcessBuilder:new(command.line)
        local p = Pipe:new()
        pb:redirectError(p)
        local ph = pb:start(function(exitCode)
          if exitCode == 0 then
            startNextCommand()
          else
            endExport(exitCode)
          end
        end)
        exportContext.process = ph
        p:readStart(function(err, data)
          if err then
            p:close()
          elseif data then
            webSocket:sendTextMessage(data)
          else
            p:close()
          end
        end)
      end
      startNextCommand()
    end
  }))
end

if config.webview.disable then
  local httpServer = require('jls.net.http.HttpServer'):new()
  httpServer:bind(config.webview.address, config.webview.port):next(function()
    createHttpContexts(httpServer)
    if config.webview.port == 0 then
      print('FCut HTTP Server available at http://localhost:'..tostring(select(2, httpServer:getAddress())))
    end
  end, function(err)
    logger:warn('Cannot bind HTTP server due to '..tostring(err))
    os.exit(1)
  end)
else
  require('jls.util.WebView').open('http://localhost:'..tostring(config.webview.port)..'/', {
    title = 'Fast Cut (Preview)',
    resizable = true,
    bind = true,
    debug = config.webview.debug,
  }):next(function(webview)
    local httpServer = webview:getHttpServer()
    createHttpContexts(httpServer)
    httpServer:createContext('/webview/(.*)', RestHttpHandler:new({
      ['fullscreen(requestJson)?method=POST&Content-Type=application/json'] = function(exchange, fullscreen)
        webview:fullscreen(fullscreen == true);
      end,
    }))
    return webview:getThread():ended()
  end):next(function()
    logger:info('WebView closed')
  end):catch(function(err)
    logger:warn('Cannot open webview due to '..tostring(err))
  end):next(function()
    execWorker:close()
    if webSocket then
      webSocket:close()
    end
  end)
end

event:loop()
