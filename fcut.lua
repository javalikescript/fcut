os.setlocale('') -- set native locale

local system = require('jls.lang.system')
local Promise = require('jls.lang.Promise')
local logger = require('jls.lang.logger')
local event = require('jls.lang.event')
local ProcessBuilder = require('jls.lang.ProcessBuilder')
local Pipe = require('jls.io.Pipe')
local File = require('jls.io.File')
local FileDescriptor = require('jls.io.FileDescriptor')
local tables = require('jls.util.tables')
local strings = require('jls.util.strings')
local Map = require('jls.util.Map')
local List = require('jls.util.List')
local HttpExchange = require('jls.net.http.HttpExchange')
local FileHttpHandler = require('jls.net.http.handler.FileHttpHandler')
local RestHttpHandler = require('jls.net.http.handler.RestHttpHandler')
local ZipFileHttpHandler = require('jls.net.http.handler.ZipFileHttpHandler')
local TableHttpHandler = require('jls.net.http.handler.TableHttpHandler')
local WebSocketUpgradeHandler = require('jls.net.http.ws').WebSocketUpgradeHandler

local FileChooser = require('FileChooser')
local Ffmpeg = require('Ffmpeg')
local CONFIG_SCHEMA = require('fcutSchema')

local function getUserDir()
  if system.isWindows() then
    return os.getenv('TEMP') or os.getenv('USERPROFILE')
  end
  return os.getenv('HOME')
end

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

local function startProcess(command, outputFile, callback)
  local pb = ProcessBuilder:new(command)
  local fd
  if outputFile then
    fd = FileDescriptor.openSync(outputFile, 'w')
    pb:redirectOutput(fd)
  end
  local ph = pb:start(function(exitCode)
    if fd then
      fd:close()
    end
    if exitCode == 0 then
      callback()
    else
      callback('The process fails with code '..tostring(exitCode))
    end
  end)
  return ph
end

local config = tables.createArgumentTable(arg, {
  helpPath = 'help',
  configPath = 'config',
  emptyPath = 'config',
  schema = CONFIG_SCHEMA
});

logger:setLevel(config.loglevel)

local cacheDir = File:new(config.cache)
if not cacheDir:isAbsolute() then
  local homeDir = File:new(getUserDir() or '.')
  if not homeDir:isDirectory() then
    error('Invalid user directory, '..homeDir:getPath())
  end
  cacheDir = File:new(homeDir, config.cache):getAbsoluteFile()
end
if not cacheDir:isDirectory() then
  if not cacheDir:mkdir() then
    error('Cannot create cache directory, '..cacheDir:getPath())
  end
end
logger:info('Cache directory is '..cacheDir:getPath())

local ffmpeg = Ffmpeg:new(cacheDir)
ffmpeg:configure(config)

local scriptFile = File:new(arg[0]):getAbsoluteFile()
local scriptDir = scriptFile:getParentFile()

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

local commandQueue = {}
local commandCount = 0
local processList = {}

local function wakeupCommandQueue()
  if commandCount < config.processCount then
    local command = table.remove(commandQueue, 1)
    if command then
      commandCount = commandCount + 1
      local ph
      ph = startProcess(command.args, command.outputFile, function(...)
        commandCount = commandCount - 1
        List.removeAll(processList, ph)
        command.callback(...)
        wakeupCommandQueue()
      end)
      table.insert(processList, ph)
    end
  end
end

local function enqueueCommand(args, id, outputFile)
  local promise, callback = Promise.createWithCallback()
  if id then
    List.removeIf(commandQueue, function(c)
      if c.id == id then
        c.callback('Cancelled')
        return true
      end
      return false
    end)
  end
  table.insert(commandQueue, {
    args = args,
    outputFile = outputFile,
    callback = callback,
    id = id,
  })
  wakeupCommandQueue()
  return promise
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
        local command = ffmpeg:createPreviewAtCommand(id, tonumber(sec), tmpFile)
        return enqueueCommand(command, 'preview')
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
        local command = ffmpeg:createProbeCommand(id)
        return enqueueCommand(command, nil, tmpFile)
      end)
    end
  }))
  httpServer:createContext('/rest/(.*)', RestHttpHandler:new({
    ['getSourceId?method=POST'] = function(exchange)
      local filename = exchange:getRequest():getBody()
      return ffmpeg:openSource(filename)
    end,
    ['checkFFmpeg?method=POST'] = function(exchange)
      local status, reason = ffmpeg:check()
      return {
        status = status,
        reason = reason,
      }
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
      local commands = exportContext.commands
      local header = {' -- export commands ------'};
      for index, command in ipairs(commands) do
        table.insert(header, '  '..tostring(index)..': '..table.concat(command, ' '))
      end
      table.insert(header, '')
      webSocket:sendTextMessage(table.concat(header, '\n'))
      local function endExport(exitCode)
        exportContext.exitCode = exitCode
        webSocket:close()
        exportContexts[exportId] = nil
      end
      local index = 0
      local function startNextCommand()
        index = index + 1
        if index > #commands then
          endExport(0)
          return
        end
        local command = commands[index]
        webSocket:sendTextMessage('\n -- starting command '..tostring(index)..'/'..tostring(#commands)..' ------\n\n')
        local pb = ProcessBuilder:new(command)
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
          if not err and data then
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

local function terminate()
  for _, ph in ipairs(processList) do
    ph:destroy()
  end
  processList = {}
  for _, exportContext in pairs(exportContexts) do
    if exportContext and exportContext.process then
      exportContext.process:destroy()
    end
  end
  exportContexts = {}
end

if config.webview.disable then
  local httpServer = require('jls.net.http.HttpServer'):new()
  httpServer:bind(config.webview.address, config.webview.port):next(function()
    createHttpContexts(httpServer)
    if config.webview.port == 0 then
      print('FCut HTTP Server available at http://localhost:'..tostring(select(2, httpServer:getAddress())))
    end
    httpServer:createContext('/admin/(.*)', RestHttpHandler:new({
      ['stop?method=POST'] = function(exchange)
        logger:info('Closing HTTP server')
        httpServer:close()
        terminate()
        --HttpExchange.ok(exchange, 'Closing')
      end,
    }))
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
  end, function(reason)
    logger:warn('Cannot open webview due to '..tostring(reason))
  end):finally(function()
    terminate()
  end)
end

event:loop()
