return {
id = "logger",
version = "1.0.0",
config = {
  file = {
    type = "string",
    description = "File to output logs to",
    default = "log.txt"
  },
  level = {
    type = "string",
    description = "Lowest level to log : 'DEBUG','INFO','WARN','ERROR'",
    default = "DEBUG",
  },
  enable = {
    type = "boolean",
    description = "Enable logging",
    default = true,
  },
  erase = {
    type = "boolean",
    description = "Overwrite the log",
    default = true,
  }
},
init = function (loaded, config)
  if config.logger.erase.value then
    assert(fs.open(config.logger.file.value, "w"), "Cannot open log file").close()
  else
    local f = assert(fs.open(config.logger.file.value, "a"), "Cannot open log file")
    f.write("--- Program start\n")
    f.close()
  end
  ---@alias level "DEBUG"|"INFO"|"WARN"|"ERROR"
  ---@type table<level,integer>
  local levelInt = {
    DEBUG = 1,
    INFO = 2,
    WARN = 3,
    ERROR = 4,
  }
  local minLevel = levelInt[config.logger.level.value]

  ---Log a sring
  ---@param level level
  ---@param msg string
  local log = function(self, level, msg)
    if not config.logger.enable.value then
      return
    elseif levelInt[level] < minLevel then
      return
    end
    local f = assert(fs.open(config.logger.file.value, "a"), "Cannot open log file")
    f.write(("[%5s][%s:%s] %s\n"):format(level, self.module, self.thread, msg))
    f.close()
  end

  ---Log a formatted string
  ---@param level level
  ---@param f string
  ---@param ... any
  local logf = function(self,level,f,...)
    self:log(level, f:format(...))
  end

  local loggerMetta = {
    log = log,
    logf = logf,
    debug = function(self,f,...)
      self:logf("DEBUG",f,...)
    end,
    info = function(self,f,...)
      self:logf("INFO",f,...)
    end,
    warn = function(self,f,...)
      self:logf("WARN",f,...)
    end,
    error = function(self,f,...)
      self:logf("ERROR",f,...)
    end
  }

  local function logger(module, thread)
    return setmetatable({
      module = module,
      thread = thread,
    }, {__index=loggerMetta})
  end
  return {
    logger = logger
  }
end
}