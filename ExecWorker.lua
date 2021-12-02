local class = require('jls.lang.class')
local Promise = require('jls.lang.Promise')
local Worker = require('jls.util.Worker')
local Map = require('jls.util.Map')
local TableList = require('jls.util.TableList')

return class.create(function(execWorker)

  function execWorker:initialize()
    self.works = {}
    self.working = false
    self.worker = Map.assign(Worker:new(function(w)
      function w:onMessage(command)
        local status, kind, code = os.execute(command)
        return self:postMessage({
          status = status,
          kind = kind,
          code = code,
        })
      end
    end), {
      onMessage = function(_, message)
        local work = table.remove(self.works, 1)
        self.working = false
        if message.status then
          work.cb()
        else
          work.cb(message.code or 0)
        end
        self:wakeup()
      end
    })
  end

  function execWorker:wakeup()
    if not self.working then
      local work = self.works[1]
      if work then
        self.working = true
        self.worker:postMessage(work.command)
      end
    end
  end

  function execWorker:execute(command, id)
    local promise, cb = Promise.createWithCallback()
    local work = {
      command = command,
      cb = cb,
      id = id,
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
