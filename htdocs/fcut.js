
function pad(n) {
  return (n < 10 ? '0' : '') + n;
}

function formatHMS(time, long) {
  var seconds = Math.floor(time) % 60;
  var minutes = Math.floor(time / 60) % 60;
  var hours = Math.floor(time / 3600);
  if ((hours === 0) && !long) {
    return '' + minutes + ':' + pad(seconds);
  }
  return '' + hours + ':' + pad(minutes) + ':' + pad(seconds);
}

function parseHMS(value) {
  var parts = value.split(':').reverse().map(function(part) {
    return parseInt(part, 10);
  });
  var seconds = parts[0] || 0;
  var minutes = parts[1] || 0;
  var hours = parts[2] || 0;
  return hours * 3600 + minutes * 60 + seconds;
}

var fileChooserCallback;

var vm = new Vue({
  el: '#app',
  data: {
    config: {},
    parts: [],
    sources: {},
    previewSrc: 'roll.png',
    destinationFilename: 'out.mp4',
    aspectRatio: '16/9',
    bars: {
      nav: true,
      time: false,
      cut: true,
      bsearch: false,
      part: false
    },
    period: 180,
    findPeriod: 180,
    findForward: true,
    exporting: false,
    duration: 0,
    partIndex: 0,
    partTime: 0,
    partEndTime: 0,
    partInfo: {},
    buffers: ['', ''],
    time: 0
  },
  methods: {
    onFileChoosed: function(names) {
      pages.navigateBack();
      if (fileChooserCallback) {
        if (names && (names.length > 1)) {
          var filenames = [];
          var path = names.shift();
          for (var i = 0; i < names.length; i++) {
            var name = names[i];
            filenames.push(path + '/' + name);
          }
          fileChooserCallback(undefined, filenames);
        } else {
          fileChooserCallback('No file selected');
        }
        fileChooserCallback = null;
      }
    },
    selectFiles: function(multiple, save) {
      var fileChooser = this.$refs.fileChooser;
      fileChooser.multiple = multiple === true;
      fileChooser.save = save === true;
      fileChooser.label = save ? 'Save' : 'Open';
      //fileChooser.refresh();
      fileChooser.list(this.config.media);
      pages.navigateTo('file-chooser');
      return new Promise(function(resolve, reject) {
        fileChooserCallback = function(reason, filenames) {
          if (!reason && filenames && (filenames.length > 0)) {
            resolve(multiple ? filenames : filenames[0]);
          } else {
            reject(reason);
          }
        };
      });
    },
    addSources: function(beforeIndex) {
      var that = this;
      return this.selectFiles(true).then(function(filenames) {
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
    loadConfig: function() {
      var that = this;
      return fetch('config/').then(function(response) {
        return response.json();
      }).then(function(config) {
        console.info('config', config);
        that.config = config.value;
      });
    },
    openSourceById: function(sourceId) {
      var that = this;
      return fetch('source/' + sourceId + '/info.json').then(function(response) {
        return response.json();
      }).then(function(info) {
        console.info('info', info);
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
      this.duration += duration;
    },
    refreshDuration: function() {
      this.duration = 0;
      for (var i = 0; i < this.parts.length; i++) {
        var part = this.parts[i];
        this.duration += part.duration;
      }
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
    exportVideo: function() {
      if (this.exporting) {
        return;
      }
      this.exporting = true;
      var that = this;
      return fetch('rest/export', {
        method: 'POST',
        headers: {
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          filename: this.destinationFilename,
          parts: this.parts,
          options: ['-f', 'mp4', '-c', 'copy']
        })
      }).finally(function() {
        that.exporting = false;
      })
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

var webSocket = new WebSocket('ws://' + location.host + '/console/');
webSocket.onmessage = function(event) {
  var newLine = event.data;
  //console.info('webSocket message', newLine);
  var buffers = vm.buffers;
  var lastLine = buffers.pop();
  var lastBuffer = buffers.pop();
  // TODO support CR/13, CR+LF/13+10, BS/8 and SUB/26
  if (newLine.charAt(0) !== '\r') {
    lastBuffer += lastLine;
  }
  lastLine = newLine;
  buffers.splice(buffers.length, 0, lastBuffer, lastLine);
};

vm.loadConfig();
pages.navigateTo('home');
