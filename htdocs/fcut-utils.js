
function hsvToRgb(h, s, v) {
  var r, g, b;
  var i = Math.floor(h * 6);
  var f = h * 6 - i;
  var p = v * (1 - s);
  var q = v * (1 - f * s);
  var t = v * (1 - (1 - f) * s);
  switch (i % 6) {
  case 0: r = v, g = t, b = p; break;
  case 1: r = q, g = v, b = p; break;
  case 2: r = p, g = v, b = t; break;
  case 3: r = p, g = q, b = v; break;
  case 4: r = t, g = p, b = v; break;
  case 5: r = v, g = p, b = q; break;
  }
  return 'rgb(' + Math.floor(r * 255) + ',' + Math.floor(g * 255) + ',' + Math.floor(b * 255) + ')';
}

function pad(n) {
  return (n < 10 ? '0' : '') + n;
}

function formatHMS(time, long) {
  var seconds = (Math.floor(time * 1000) / 1000) % 60;
  var minutes = Math.floor(time / 60) % 60;
  var hours = Math.floor(time / 3600);
  if ((hours === 0) && !long) {
    return '' + minutes + ':' + pad(seconds);
  }
  return '' + hours + ':' + pad(minutes) + ':' + pad(seconds);
}

function parseHMS(value) {
  var parts = value.split(':').reverse().map(function(part) {
    return parseFloat(part);
  });
  var seconds = parts[0] || 0;
  var minutes = parts[1] || 0;
  var hours = parts[2] || 0;
  return hours * 3600 + minutes * 60 + seconds;
}

function computeAspectRatio(value) {
  if (typeof value === 'string') {
    var values = value.split(':');
    value = parseFloat(values[0]) / parseFloat(values[1]);
  } else if (typeof value !== 'number') {
    return 0;
  }
  if (isNaN(value)) {
    return 0;
  }
  return Math.floor(value * 1000000) / 1000000;
}

var messageCallback = null;

function onMessageClosed(response) {
  pages.navigateBack();
  if (messageCallback) {
    var cb = messageCallback;
    messageCallback = null;
    if (response) {
      cb(undefined, response);
    } else {
      cb('Cancelled');
    }
  }
}

function showMessage() {
  if (messageCallback) {
    throw new Error('Message already shown');
  }
  pages.navigateTo('message');
  return new Promise(function(resolve, reject) {
    messageCallback = function(reason, result) {
      if (reason) {
        reject(reason);
      } else {
        resolve(result);
      }
    };
  });
}

function withoutExtension(filename) {
  if (typeof filename !== 'string') {
    return filename;
  }
  return filename.replace(/\.[^/\\.]+$/, '');
}

function basename(filename) {
  if (typeof filename !== 'string') {
    return filename;
  }
  return filename.replace(/^.*[/\\]([^/\\]+)$/, '$1');
}

function dirname(filename) {
  if (typeof filename !== 'string') {
    return filename;
  }
  return filename.replace(/[/\\][^/\\]+$/, '');
}

var fileChooserCallback = null;

function onFileChoosed(names) {
  pages.navigateBack();
  if (fileChooserCallback) {
    var cb = fileChooserCallback;
    fileChooserCallback = null;
    if (names && (names.length > 1)) {
      var filenames = [];
      var path = names.shift();
      for (var i = 0; i < names.length; i++) {
        var name = names[i];
        filenames.push(path + '/' + name);
      }
      cb(undefined, filenames);
    } else {
      cb('No file selected');
    }
  }
}

function chooseFiles(fileChooser, multiple, save, path, extention, name) {
  fileChooser.multiple = multiple === true;
  fileChooser.save = save === true;
  fileChooser.label = save ? 'Save' : 'Open';
  fileChooser.extention = extention || '';
  fileChooser.name = name || '';
  if (path) {
    fileChooser.list(path);
  } else {
    fileChooser.refresh();
  }
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
}

function getFile(path) {
  return fetch('rest/getFile', {
    method: 'POST',
    headers: {
      "Content-Type": "text/plain"
    },
    body: path
  }).then(function(response) {
    return response.json();
  });
}

function checkFile(path) {
  return getFile(path).then(function() {
    return Promise.reject(path);
  }, function() {
    return Promise.resolve(path);
  });
}

function writeFile(path, data, overwrite) {
  return fetch('rest/writeFile', {
    method: 'POST',
    headers: {
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      path: path,
      data: data,
      overwrite: overwrite
    })
  });
}

function readFile(filename, asJson) {
  return fetch('rest/readFile', {
    method: 'POST',
    headers: {
      "Content-Type": "text/plain"
    },
    body: filename
  }).then(function(response) {
    if (asJson) {
      return response.json();
    }
    return response.text();
  });
}
