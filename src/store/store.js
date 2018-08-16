import Vue from 'vue'
import Vuex from 'vuex'
import client from './../client/client.js'
Vue.use(Vuex);

const state = {
  running: '',
  items: [],
  hashes: [],
  cracked: [],
  history: [],
  item: {
    name: '',
    dictionary: '',
    dictionary2: '',
    rules: '',
    mask: '',
    hash: '',
    hashmode: '',
    hashid: '',
    hashstring: '',
    files: [],
    latitude: '',
    longitude: '',
  },
  progress: {},
  cmd: '',
  pid: '',
  isRunning: false,
  pidActive: '',
  showModal: false,
};

let isEqual = function (value, other) {
  let type = Object.prototype.toString.call(value);
  if (type !== Object.prototype.toString.call(other)) return false;
  if (['[object Array]', '[object Object]'].indexOf(type) < 0) return false;
  let valueLen = type === '[object Array]' ? value.length : Object.keys(value).length;
  let otherLen = type === '[object Array]' ? other.length : Object.keys(other).length;
  if (valueLen !== otherLen) return false;
  let compare = function (item1, item2) {
    let itemType = Object.prototype.toString.call(item1);
    if (['[object Array]', '[object Object]'].indexOf(itemType) >= 0) {
      if (!isEqual(item1, item2)) return false;
    }
    else {
      if (itemType !== Object.prototype.toString.call(item2)) return false;
      if (itemType === '[object Function]') {
        if (item1.toString() !== item2.toString()) return false;
      } else {
        if (item1 !== item2) return false;
      }
    }
  };
  if (type === '[object Array]') {
    for (let i = 0; i < valueLen; i++) {
      if (compare(value[i], other[i]) === false) return false;
    }
  } else {
    for (let key in value) {
      if (value.hasOwnProperty(key)) {
        if (compare(value[key], other[key]) === false) return false;
      }
    }
  }
  return true;
};


const actions = {
  get_pending(context){
    let _this = this
    client.get_pending()
      .then(function(response){
        console.log('context.getters.getPending', context.getters.getPending)
        console.log('pending..', response.data.pending)
        console.log('equal?', isEqual(context.getters.getPending, response.data.pending))
        if (!isEqual(context.getters.getPending, response.data.pending)) {
          _this.commit('load_items', response.data)
        }
      })
      .catch(function(error) {
        console.error('Error get pending:', error)
      })
  },

  create_pending(context, params) {
    return client.create_pending(params.name, params.dictionary, params.dictionary2,
      params.rules, params.mask, params.hash, params.hashmode, params.hashstring, params.hashid)
  },

  insert_hash(context, params) {
    return client.insert_hash(params.name, params.hash, params.hashmode, params.hashstring,
      params.latitude, params.longitude)
  },

  login(context, params) {
    return client.login(params.handle, params.password)
  },

  promote_next(context) {
    if (context.pid) client.stop(context.pid)
    return client.promote_next()
  },

  start(context) {
    let _this = this
    client.start()
      .then(function(response){
        _this.commit('start', response.data)
      })
      .catch(function(error) {
        console.error('error in start', error)
      })
  },
  stop(context, id) {
    let _this = this
    _this.commit('stop')
    return client.stop(context.getters.getPid)
  },

  stopnow(context) {
    let _this = this
    _this.commit('stop')
    return client.stop(context.pid)
  },

  get_progress(context) {
    let _this = this
    client.get_progress()
      .then(function(response){
        _this.commit('get_progress', response.data)
      })
      .catch(function(error) {
        console.error('error in get_progress', error)
      })
  },

  get_running(context) {
    let _this = this
    client.get_running()
      .then(function(response){
        _this.commit('load_running', response.data)
      })
      .catch(function(error) {
        console.error('error in get_running', error)
      })
  },

  clear_running(context) {
    client.clear_running()
    return true
  },

  clear_running(context) {
    let _this = this
    client.clear_pending()
      .then(function(response) {
        _this.commit('clear_pending')
      })
      .catch(function(error) {
        console.log('error in clear_pending', error)
      })
  },

  get_cracked(context) {
    let _this = this
    client.get_cracked()
      .then(function(response){
        _this.commit('load_cracked', response.data)
      })
      .catch(function(error) {
        console.error('error in get_cracked', error)
      })
  },


  get_hashes(context) {
    let _this = this
    client.get_hashes()
      .then(function(response){
        _this.commit('load_hashes', response.data)
      })
      .catch(function(error) {
        console.error('error in get_hashes', error)
      })
  },

  get_history(context, id) {
    let _this = this
    client.get_history(id)
      .then(function(response){
        _this.commit('load_history', response.data)
      })
      .catch(function(error) {
        console.error('error in get_history', error)
      })
  },

  insert_cracked(context) {
    let _this = this
    client.insert_cracked()
      .then(function(response) {
        _this.commit('insert_cracked', response.data)
      })
      .catch(function(error) {
        console.log('error in insert_cracked', error)
      })
  },
  clear_cracked(context) {
    let _this = this
    client.clear_cracked()
      .then(function(response) {
        _this.commit('clear_cracked')
      })
      .catch(function(error) {
        console.log('error in clear_cracked', error)
      })
  },
  clear_active(context) {
    let _this = this
    client.clear_active()
      .then(function(response) {
        _this.commit('load_active', response.data)
      })
      .catch(function(error) {
        console.error('error in get_running', error)
      })
  },

  load_pid_active(context, id) {
    let _this = this
    client.pid_active(id)
      .then(function(response) {
        _this.commit('load_pid_active', response.data)
      })
      .catch(function(error) {
        console.error('error in load_pid_active', error)
      })
  },

  delete_hash(context, id) {
    let _this = this
    client.delete_hash(id)
      .then(function(response) {
        console.log('response', response)
        // _this.commit('load_pid_active', response.data)
      })
      .catch(function(error) {
        console.error('error in load_pid_active', error)
      })
  },

  show_modal(context) {
    let _this = this
    _this.commit('show_modal')
  },
  hide_modal(context) {
    let _this = this
    _this.commit('hide_modal')
  }
};

const mutations = {
  load_pid_active (context, data) { context.pidActive = data.pid },
  get_progress (context, data) { context.progress = data },
  load_items (context, data) { context.items = data.pending },
  load_running (context, data) { context.running = data.running || ''; },
  load_cracked (context, data) { context.cracked = data.cracked || ''; },
  load_hashes (context, data) { context.hashes = data || ''; },
  load_history (context, data) { context.history = data || ''; },
  insert_cracked (context) { context.cracked = data.cracked },
  load_item (context, data) { context.item = data.item },
  clear_items (context) { context.items = [] },
  clear_item(context) { context.item = { title: '' }},
  clear_running(context) { context.running = [] },
  clear_pending(context) { context.items = [] },
  clear_cracked(context) { context.cracked = [] },
  show_modal(context) { context.showModal = true; },
  hide_modal(context) { context.showModal = false; },
  stop(context) { context.isRunning = false; },
  start(context, data) {
    console.log('start', data);
    // context.cmd = data.cmd;
    context.pid = data.pid;
    context.isRunning = true;
  }
};

const getters = {
  getHashes (state){ return state.hashes },
  getHistory (state){ return state.history },
  getItem (state){ return state.item },
  getItems (state){ return state.items },
  getPending (state){ return state.items },
  getRunning (state) { return state.running },
  getProgress (state) { return state.progress },
  getCmd(state) { return state.cmd },
  getPid(state) { return state.pid },
  getIsRunning(state) { return state.isRunning },
  getCracked(state) { return state.cracked },
  getPidActive(state) { return state.pidActive },
  getShowModal(state) { return state.showModal; }
};

export default new Vuex.Store({
  state: state,
  actions: actions,
  mutations: mutations,
  getters: getters
});
