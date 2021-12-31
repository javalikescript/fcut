local class = require('jls.lang.class')
local Promise = require('jls.lang.Promise')
local Worker = require('jls.util.Worker')
local Map = require('jls.util.Map')

return class.create(function(serialWorker)

  function serialWorker:initialize(fn)
    local code = "local factory = load("..string.format('%q', string.dump(fn))..", nil, 'b')"..
    [[
      local w = ...
      local fn = factory()
      function w:onMessage(order)
        local result = fn(order)
        return self:postMessage(result)
      end
    ]]
    self.worker = Map.assign(Worker:new(load(code, nil, 't')), {
      onMessage = function(_, result)
        local cb = self.workCallback
        if cb then
          self.workCallback = false
          cb(nil, result)
        end
        self:wakeup()
      end
    })
    self.workCallback = false
    self.works = {}
  end

  function serialWorker:wakeup()
    if not self.workCallback then
      local work = table.remove(self.works, 1)
      if work then
        self.workCallback = work.cb
        self.worker:postMessage(work.order)
      end
    end
  end

  function serialWorker:process(order)
    local promise, cb = Promise.createWithCallback()
    local work = {
      order = order,
      cb = cb,
    }
    table.insert(self.works, work)
    self:wakeup()
    return promise
  end

  function serialWorker:close()
    self.worker:close()
  end

end)