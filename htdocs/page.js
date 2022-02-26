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
