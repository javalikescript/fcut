
var partRegExp = /^\n -- starting command ([0-9]+)\/([0-9]+)\s/;
var timeRegExp = /^frame=.*\stime=([0-9:.]+)\s/;

var vm = new Vue({
  el: '#app',
  data: {
    config: {},
    sources: {},
    previewSrc: 'roll.png',
    destinationFilename: 'out.mp4',
    aspectRatio: 0,
    bars: {
      nav: true,
      time: false,
      cut: true,
      bsearch: false,
      project: false
    },
    period: 180,
    findPeriod: 180,
    findForward: true,
    exportId: false,
    exportFormat: 'mp4',
    exportVideoCodec: 'copy',
    exportAudioCodec: 'copy',
    exportEnableSubtitle: false,
    duration: 0,
    parts: [],
    partIndex: 0,
    partTime: 0,
    partEndTime: 0,
    partInfo: {},
    time: 0,
    logBuffer: '',
    logLine: '',
    logTime: 0,
    logPartIndex: 0,
    logPartCount: 0,
    logDuration: 0,
    logPermil: 0,
    keepFileChooserPath: false,
    messageTitle: '',
    messageLines: []
  },
  methods: {
    showMessage: function(text, title) {
      if (Array.isArray(text)) {
        this.messageLines = text;
      } else if (typeof text === 'string') {
        this.messageLines = text.split('\n');
      } else {
        this.messageLines = ['Are you sure?'];
      }
      this.messageTitle = title || 'Message';
      return showMessage();
    },
    selectFiles: function(multiple, save, extention) {
      var path = this.keepFileChooserPath ? undefined : this.config.media;
      this.keepFileChooserPath = true;
      return chooseFiles(this.$refs.fileChooser, multiple, save, path, extention);
    },
    addSources: function(beforeIndex) {
      var that = this;
      return this.selectFiles(true, false, '.m2ts').then(function(filenames) {
        return Promise.all(filenames.map(function(filename) {
          return that.openSource(filename, beforeIndex).then(function(sourceId) {
            that.addSource(sourceId, beforeIndex);
          });
        })).then(function() {
          that.goTo(that.time);
        });
      });
    },
    openSource: function(filename) {
      var that = this;
      console.info('openSource("' + filename + '")');
      return fetch('rest/getSourceId', {
        method: 'POST',
        headers: {
          "Content-Type": "text/plain"
        },
        body: filename
      }).then(function(response) {
        return response.text();
      }).then(function(sourceId) {
        return that.openSourceById(sourceId);
      });
    },
    loadConfig: function(boot) {
      var that = this;
      return Promise.all([fetch('config/').then(function(response) {
        return response.json();
      }), fetch('/rest/checkFFmpeg', { method: 'POST' }).then(function(response) {
        return response.json();
      })]).then(function(values) {
        var config = values[0];
        var checkFFmpeg = values[1];
        //console.info('config', config, 'checkFFmpeg', checkFFmpeg);
        that.config = config.value;
        if (boot) {
          if (checkFFmpeg.status) {
            if (that.config.project) {
              that.loadProjectFromFile(that.config.project).then(function() {
                pages.navigateTo('preview');
              });
            } else {
              pages.navigateTo('home');
            }
          } else {
            pages.navigateTo('missingConfig');
          }
        }
      });
    },
    openSourceById: function(sourceId) {
      var that = this;
      return fetch('source/' + sourceId + '/info.json').then(function(response) {
        return response.json();
      }).then(function(info) {
        //console.info('info', info);
        that.sources[sourceId] = info;
        return sourceId;
      });
    },
    addSource: function(sourceId, beforeIndex) {
      var info = this.sources[sourceId];
      var duration = Math.floor(parseFloat(info.format.duration) - 1.1);
      var part = {
        sourceId: sourceId,
        duration: duration,
        from: 0,
        to: duration
      };
      if ((beforeIndex >= 0) && (beforeIndex < this.parts.length)) {
        this.parts.splice(beforeIndex, 0, part);
      } else {
        this.parts.push(part);
      }
      this.refreshParts();
    },
    refreshParts: function() {
      var duration = 0;
      for (var i = 0; i < this.parts.length; i++) {
        var part = this.parts[i];
        duration += part.duration;
      }
      if (this.parts.length > 0) {
        var part = this.parts[0];
        var info = this.sources[part.sourceId];
        for (var i = 0; i < info.streams.length; i++) {
          var stream = info.streams[i];
          if ((stream.codec_type === 'video') && stream.display_aspect_ratio) {
            this.aspectRatio = computeAspectRatio(stream.display_aspect_ratio);
            break;
          }
        }
      }
      this.duration = duration;
    },
    navigateOnPreviewClick: function(event) {
      var rect = event.target.getBoundingClientRect();
      var x = event.clientX - rect.left;
      var t = Math.floor(this.duration * x / rect.width);
      this.navigateTo(t);
    },
    navigateOnClick: function(event, targetId) {
      var target = targetId ? document.getElementById(targetId) : event.target;
      var rect = target.getBoundingClientRect();
      var x = event.clientX - rect.left;
      var m = rect.width / 100;
      var t = Math.floor(this.duration * (x - m) / (rect.width - m * 2));
      this.navigateTo(t);
    },
    findPartAndTime: function(time) {
      if ((this.parts.length > 0) && (time >= 0) && (time <= this.duration)) {
        var absTime = 0;
        for (var i = 0; i < this.parts.length; i++) {
          var part = this.parts[i];
          var relTime = time - absTime;
          if (part.duration > relTime) {
            return {
              index: i,
              part: part,
              relTime: relTime,
              time: absTime
            };
          }
          absTime += part.duration;
        }
        var i = this.parts.length - 1;
        var part = this.parts[i];
        return {
          index: i,
          part: part,
          relTime: part.duration,
          time: absTime - part.duration
        };
      }
      console.info('no part found at ' + time);
    },
    goTo: function(time) {
      if (time < 0) {
        time = 0;
      } else if (time > this.duration) {
        time = this.duration;
      }
      this.time = time;
      var at = this.findPartAndTime(time);
      if (at) {
        this.previewSrc = 'source/' + at.part.sourceId + '/' + (at.part.from + at.relTime) + '.jpg';
        this.partIndex = at.index;
        this.partTime = at.time;
        this.partEndTime = at.time + at.part.duration;
        this.partInfo = this.sources[at.part.sourceId];
      } else {
        this.previewSrc = 'roll.png';
        this.partIndex = 0;
        this.partTime = 0;
        this.partEndTime = 0;
        this.partInfo = {}
      }
    },
    movePart: function(atIndex, toIndex) {
      var a = this.parts[atIndex];
      var b = this.parts[toIndex];
      if (a && b) {
        this.parts[atIndex] = b;
        this.parts[toIndex] = a;
        this.goTo(this.time);
      }
    },
    removePart: function(atIndex) {
      if ((atIndex >= 0) && (atIndex < this.parts.length)) {
        var part = this.parts[atIndex];
        if (part) {
          this.parts.splice(atIndex, 1);
          console.info('part ' + atIndex + ' removed #' + this.parts.length);
          this.duration -= part.duration;
          this.goTo(this.time);
        }
      }
    },
    split: function() {
      var at = this.findPartAndTime(this.time);
      if (at && (at.relTime > 0)&& (at.relTime < at.part.duration)) {
        var part = at.part;
        var splitTime = part.from + at.relTime;
        var part1 = {
          sourceId: part.sourceId,
          duration: at.relTime,
          from: part.from,
          to: splitTime
        };
        var part2 = {
          sourceId: part.sourceId,
          duration: part.duration - at.relTime,
          from: splitTime,
          to: part.to
        };
        this.partTime = this.time;
        this.partEndTime = this.time + part2.duration;
        this.parts.splice(at.index, 1, part1, part2);
        console.info('part ' + at.index + ' split #' + this.parts.length);
      }
    },
    findNext: function(forward) {
      if ((forward !== this.findForward) || (this.findPeriod < this.period)) {
        this.findPeriod = Math.floor(this.findPeriod / 2);
        this.findForward = forward;
      }
      this.goTo(this.time + (this.findForward ? 1 : -1) * this.findPeriod);
    },
    navigateTo: function(time) {
      this.findForward = true;
      this.findPeriod = this.period;
      this.goTo(typeof time === 'number' ? time : this.time);
    },
    move: function(delta) {
      this.navigateTo(this.time + delta);
    },
    stopExport: function() {
      return fetch('rest/cancelExport', {
        method: 'POST',
        headers: {
          "Content-Type": "text/plain"
        },
        body: this.exportId
      }).then(function() {
      });
    },
    logMessage: function(content) {
      if (this.logCR) {
        this.logLine = '';
        this.logCR = false;
      }
      var found = timeRegExp.exec(content);
      if (found) {
        var time = parseHMS(found[1]);
        if (time) {
          this.logTime = this.logCompletedTime + time;
          this.logPermil = Math.floor(this.logTime * 1000 / this.logDuration)
        }
      } else {
        found = partRegExp.exec(content);
        if (found) {
          this.logPartIndex = parseInt(found[1], 10);
          if (this.logPartIndex <= this.logPartCount) {
            this.logCompletedTime = this.logTime;
          } else {
            this.logCompletedTime = 0;
          }
        }
      }
      var index = content.lastIndexOf('\n');
      if (index >= 0) {
        this.logBuffer += '\n' + this.logLine + content.substring(0, index);
        this.logLine = content.substring(index + 1);
      } else {
        index = content.lastIndexOf('\r');
        if (index >= 0) {
          if (index == content.length - 1) {
            this.logLine += content.substring(0, index);
            this.logCR = true;
          } else {
            this.logLine = content.substring(index + 1);
          }
        } else {
          this.logLine += content;
        }
      }
    },
    startExport: function() {
      if (this.exportId) {
        return;
      }
      var options = [];
      if (this.exportFormat !== '-') {
        options.push('-f', this.exportFormat);
      }
      if (this.exportVideoCodec !== '-') {
        options.push('-vcodec', this.exportVideoCodec);
      } else {
        options.push('-vn');
      }
      if (this.exportAudioCodec !== '-') {
        options.push('-acodec', this.exportAudioCodec);
      } else {
        options.push('-an');
      }
      if (!this.exportEnableSubtitle) {
        options.push('-sn');
      }
      var request = {
        filename: this.destinationFilename,
        parts: this.parts,
        options: options
      };
      this.logBuffer = '';
      this.logLine = '';
      this.logCR = false;
      this.logPartCount = this.parts.length;
      this.logDuration = this.duration;
      this.logTime = 0;
      this.logCompletedTime = 0;
      this.logPermil = 0;
      var that = this;
      return checkFile(this.destinationFilename).catch(function(filename) {
        return that.showMessage('The file exists.\n' + filename + '\nDo you want to overwrite?');
      }).then(function() {
        return fetch('rest/export', {
          method: 'POST',
          headers: {
            "Content-Type": "application/json"
          },
          body: JSON.stringify(request)
        });
      }).then(function(response) {
        return response.text();
      }).then(function(exportId) {
        that.exportId = exportId;
        var webSocket = new WebSocket('ws://' + location.host + '/console/' + exportId);
        webSocket.onmessage = function(event) {
          that.logMessage(event.data);
        };
        webSocket.onclose = function() {
          that.exportId = false;
        };
      });
    },
    saveProjectToJson: function() {
      var sources = {};
      for (var sourceId in this.sources) {
        var source = this.sources[sourceId]
        sources[sourceId] = source.format.filename; // TODO change
      }
      var project = {
        parts: this.parts,
        sources: sources
      };
      return project;
    },
    loadProjectFromJson: function(project) {
      var that = this;
      //console.info('projet', project);
      return Promise.all(Object.keys(project.sources).map(function(sourceId) {
        var filename = project.sources[sourceId];
        return that.openSource(filename).then(function(id) {
          if (id !== sourceId) {
            return Promise.reject('Source id does not match');
          }
        });
      })).then(function() {
        that.parts = project.parts;
        that.refreshParts();
        that.navigateTo(0);
      });
    },
    loadProjectFromFile: function(filename) {
      var that = this;
      return readFile(filename, true).then(function(prj) {
        return that.loadProjectFromJson(prj);
      });
    },
    saveProject: function() {
      var content = JSON.stringify(this.saveProjectToJson(), null, 2)
      var that = this;
      return this.selectFiles(false, true, '.json').then(function(filename) {
        return checkFile(filename).catch(function(filename) {
          return that.showMessage('The file exists.\n' + filename + '\nDo you want to overwrite?');
        }).then(function() {
          writeFile(filename, content, true);
        });
      });
    },
    openProject: function() {
      var that = this;
      return this.selectFiles(false, false, '.json').then(function(filename) {
        return that.loadProjectFromFile(filename);
      });
    }
  },
  computed: {
    timeHMS: {
      get: function() {
        return formatHMS(this.time);
      },
      set: function(newValue) {
        this.time = parseHMS(newValue);
      }
    },
    periodHMS: {
      get: function() {
        return formatHMS(this.period);
      },
      set: function(newValue) {
        this.period = parseHMS(newValue);
      }
    }
  }
});

vm.loadConfig(true);
