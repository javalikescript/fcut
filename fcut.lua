os.setlocale('') -- set native locale

local system = require('jls.lang.system')
local Promise = require('jls.lang.Promise')
local logger = require('jls.lang.logger')
local loader = require('jls.lang.loader')
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

-- Project required modules

local FileChooser = require('FileChooser')
local Ffmpeg = require('Ffmpeg')
local CONFIG_SCHEMA = require('fcutSchema')

-- Helper functions

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

local function createProcessBuilder(...)
  local pb = ProcessBuilder:new(...)
  -- hide the subprocess console window that would normally be created
  pb.hide = true
  return pb
end

local function startProcess(command, outputFile, callback)
  local pb = createProcessBuilder(command)
  local fd
  if outputFile then
    fd = FileDescriptor.openSync(outputFile, 'w')
    pb:redirectOutput(fd)
  end
  local ph = pb:start()
  ph:ended():next(function(exitCode)
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

-- Extracts configuration from command line arguments
local config = tables.createArgumentTable(arg, {
  helpPath = 'help',
  configPath = 'config',
  emptyPath = 'config',
  schema = CONFIG_SCHEMA
});

-- Apply configured log level
logger:setLevel(config.loglevel)

-- Disable native open file dialog if necessary
if config.webview.native and config.webview.disable or not loader.tryRequire('win32') then
  config.webview.native = false
end

-- Application local variables

local scriptFile = File:new(arg[0]):getAbsoluteFile()
local scriptDir = scriptFile:getParentFile()

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
local exportContexts = {}
local serialWorker

-- Set up the cache directory
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

-- Application local functions

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
  if serialWorker then
    serialWorker:close()
    serialWorker = nil
  end
end

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

-- HTTP contexts used by the web application
local httpContexts = {
  ['/(.*)'] = FileHttpHandler:new(File:new(scriptDir, 'htdocs'), nil, 'fcut.html'),
  ['/config/(.*)'] = TableHttpHandler:new(config, nil, true),
  ['/assets/(.*)'] = assetsHandler,
}

-- Create the HTTP contexts used by the web application
local function createHttpContexts(httpServer)
  logger:info('HTTP Server bound on port '..tostring(select(2, httpServer:getAddress())))
  -- Context to retrieve and cache a movie image at a specific time
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
  -- Context to retrieve and cache a movie information
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
  -- Context for the application REST API
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
  -- Context that handle the export commands and output to a WebSocket
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
        local pb = createProcessBuilder(command)
        local p = Pipe:new()
        pb:redirectError(p)
        local ph = pb:start()
        ph:ended():next(function(exitCode)
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

-- Start the application as an HTTP server or a WebView
if config.webview.disable then
  local httpServer = require('jls.net.http.HttpServer'):new()
  httpServer:bind(config.webview.address, config.webview.port):next(function()
    for path, handler in pairs(httpContexts) do
      httpServer:createContext(path, handler)
    end
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
    contexts = httpContexts,
  }):next(function(webview)
    local httpServer = webview:getHttpServer()
    createHttpContexts(httpServer)
    httpServer:createContext('/webview/(.*)', RestHttpHandler:new({
      ['fullscreen(requestJson)?method=POST&Content-Type=application/json'] = function(exchange, fullscreen)
        webview:fullscreen(fullscreen == true);
      end,
      ['selectFiles(requestJson)?method=POST&Content-Type=application/json'] = function(exchange, obj)
        if serialWorker then
          return serialWorker:process(obj)
        end
        HttpExchange.notFound(exchange, 'Not available')
        return false
      end,
    }))
    if config.webview.native then
      serialWorker = require('jls.util.SerialWorker'):new()
      local function getFileName(message)
        local win32 = require('win32')
        win32.SetWindowOwner()
        if message then
          if message.save then
            return {win32.GetSaveFileName()}
          end
          local names = table.pack(win32.GetOpenFileName(message.multiple))
          local dir = table.remove(names, 1)
          if #names == 0 then
            return {dir}
          end
          local filenames = {}
          for _, name in ipairs(names) do
            table.insert(filenames, dir..'\\'..name)
          end
          return filenames
        end
      end
      function serialWorker:process(order)
        if self.workCallback then
          return Promise.reject()
        end
        return self:call(getFileName, order)
      end
    end
    return webview:getThread():ended()
  end):next(function()
    logger:info('WebView closed')
  end, function(reason)
    logger:warn('Cannot open webview due to '..tostring(reason))
  end):finally(function()
    terminate()
  end)
end

-- Process events until the end
event:loop()
