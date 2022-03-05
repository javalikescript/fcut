var pages = {
  name: '',
  fallbackName: '',
  names: {},
  navigationHistory: [],
  navigateTo: function(name, replace) {
    if (this.name == name) {
      return;
    }
    var previousPage = this.names[this.name];
    this.name = name;
    if (replace) {
      this.navigationHistory.pop();
    }
    this.navigationHistory.push(name);
    var page = this.names[name];
    if (previousPage) {
      previousPage.$emit('page-hide', previousPage);
    }
    if (page) {
      page.$emit('page-show', page);
    }
  },
  current: function() {
    return this.names[this.name];
  },
  dispatchKey: function(event) {
    var tagName = event.target.tagName.toUpperCase();
    if (tagName !== 'INPUT') {
      var eventName = event.key;
      if (eventName.length > 1) {
        eventName = eventName.toLowerCase();
      }
      if (eventName.substring(0, 5) === 'arrow') {
        eventName = eventName.substring(5);
      }
      if (event.altKey) {
        eventName = 'alt-' + eventName;
      }
      if (event.ctrlKey) {
        eventName = 'ctrl-' + eventName;
      }
      //console.log('dispatchKey(): ' + eventName, event, this);
      var page = this.names[this.name];
      if (page) {
        page.$emit('page-key-' + eventName, event);
      }
    }
  },
navigateBack: function() {
    if (this.navigationHistory.length > 1) {
      this.navigationHistory.pop();
      this.name = this.navigationHistory[this.navigationHistory.length - 1];
    } else if (this.fallbackName in this.names) {
      this.navigateTo(this.fallbackName);
    }
  }
};

Vue.component('page', {
  data: function() {
    return {
      pages: pages,
      hideClass: 'hideRight'
    };
  },
  props: ['name'],
  template: '<section :ref="name" v-bind:name="name" v-bind:class="[{page: true}, pages.name === name ? \'\' : hideClass]">'
    + '<slot>Article</slot></section>',
  created: function() {
    this.pages.names[this.name] = this;
    if (this.pages.fallbackName === '') {
      this.pages.fallbackName = this.name;
    }
  }
});
