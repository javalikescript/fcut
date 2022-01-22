return {
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
    mediaFilter = {
      title = 'The media file filter',
      type = 'string',
      default = '.m2ts',
    },
    project = {
      title = 'A project file to load',
      type = 'string',
    },
    processCount = {
      title = 'The maximum number of running processes',
      type = 'integer',
      default = 2,
      minimum = 1,
      maximum = 32,
    },
    ffmpeg = {
      title = 'The ffmpeg path',
      type = 'string',
      default = (require('jls.lang.system').isWindows() and 'ffmpeg\\ffmpeg.exe' or '/usr/bin/ffmpeg'),
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
        native = {
          title = 'Enable native open file dialog',
          type = 'boolean',
          default = true,
        },
      }
    },
  },
}