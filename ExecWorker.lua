local class = require('jls.lang.class')
local Promise = require('jls.lang.Promise')
local Worker = require('jls.util.Worker')
local Map = require('jls.util.Map')
local TableList = require('jls.util.TableList')
local system = require('jls.lang.system')

local nullFilename = system.isWindows() and 'NUL' or '/dev/null'

return class.create(function(execWorker)

  function execWorker:initialize()
    self.works = {}
    self.working = false
    self.worker = Map.assign(Worker:new(function(w)
      function w:onMessage(message)
        local status, kind, code
        if message.pipe then
          local f = io.popen(message.command)
          if f then
            self:postMessage('Process started, '..tostring(message.command))
            repeat
              local d = f:read(message.pipe)
              self:postMessage(d)
            until d == nil
            status, kind, code = f:close()
            if not status then
              self:postMessage('Process terminated with exit code '..tostring(code))
            end
          else
            status, kind, code = false, 'popen', 0
          end
        else
          status, kind, code = os.execute(message.command)
        end
        return self:postMessage({
          status = status,
          kind = kind,
          code = code,
        })
      end
    end), {
      onMessage = function(_, message)
        local work
        if type(message) == 'string' or message == nil then
          work = self.works[1]
          if work.sh then
            work.sh(message)
          end
          return
        elseif type(message) == 'table' then
          work = table.remove(self.works, 1)
          self.working = false
          if message.status then
            work.cb()
          else
            work.cb(message.code or 0)
          end
          self:wakeup()
        else
          error('Bad message '..tostring(message))
        end
      end
    })
  end

  function execWorker:wakeup()
    if not self.working then
      local work = self.works[1]
      if work then
        self.working = true
        self.worker:postMessage({
          command = work.command,
          pipe = work.sh and (work.rf or 'L'),
        })
      end
    end
  end

  function execWorker:execute(command, id, sh, redirect, rf)
    local suffix = ''
    if redirect == 'both' then
      suffix = ' 2>&1'
    elseif redirect == 'error' then
      suffix = ' 2>&1 1>'..nullFilename
    elseif redirect == 'output' then
      suffix = ' 2>'..nullFilename
    end
    local promise, cb = Promise.createWithCallback()
    local work = {
      command = command..suffix,
      cb = cb,
      id = id,
      sh = sh,
      redirect = redirect,
      rf = rf,
    }
    if id then
      TableList.removeIf(self.works, function(w, i)
        if i > 1 and w.id == id then
          w.cb('Cancelled')
          return true
        end
        return false
      end)
    end
    table.insert(self.works, work)
    self:wakeup()
    return promise
  end

  function execWorker:close()
    self.worker:close()
  end

end)
