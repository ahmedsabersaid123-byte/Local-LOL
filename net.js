// Api (HTTP) + Net (WebSocket relay + lobby state). The room host's browser is authoritative.
const Api = {
  token: "", user: null,
  async call(endpoint, data = {}) {
    data.token = this.token;
    try {
      const r = await fetch("/" + endpoint, { method: "POST", body: JSON.stringify(data) });
      const j = await r.json();
      if (j.user) this.user = j.user;
      if (j.token) this.token = j.token;
      return j;
    } catch (e) { return { error: "السيرفر مش بيرد" }; }
  },
  owned(id) { return !!(this.user && this.user.owned.includes(id)); },
  equipped(slot) { return (this.user && this.user.equipped[slot]) || ""; },
  look() {
    const u = this.user;
    return { body: u.body, skin: u.equipped.skin, outfit: u.equipped.outfit, face_b64: u.face_b64 || "" };
  },
};

const faceCache = {}; // username -> b64 (fetched on demand)
async function faceOf(username) {
  if (username in faceCache) return faceCache[username];
  faceCache[username] = "";
  const r = await Api.call("profile", { username });
  faceCache[username] = r.face_b64 || "";
  return faceCache[username];
}

const Net = {
  ws: null, myId: 1, hostId: 1, inRoom: false, isHost: false, solo: false, inMatch: false,
  players: {}, bots: [], mode: "tdm", bossLevel: 1, seed: 0,
  onLobby: null, onStatus: null, onMsg: null, onStart: null, onLeft: null,
  _ping: null,

  status(t) { if (this.onStatus) this.onStatus(t); },

  myInfo() {
    const u = Api.user, l = Api.look();
    return { username: u.username, name: u.display_name, team: 0, look: { body: l.body, skin: l.skin, outfit: l.outfit } };
  },

  _open() {
    return new Promise((resolve, reject) => {
      this.close(true);
      const proto = location.protocol === "https:" ? "wss://" : "ws://";
      const ws = new WebSocket(proto + location.host + "/ws");
      this.ws = ws;
      ws.onopen = () => ws.send(JSON.stringify({ t: "auth", token: Api.token }));
      ws.onerror = () => reject(new Error("مفيش اتصال"));
      ws.onclose = () => { if (this.ws === ws) { this.ws = null; if (this.inRoom && !this.solo) this._lost("الاتصال اتقطع"); } };
      ws.onmessage = (e) => {
        const m = JSON.parse(e.data);
        if (m.t === "ready") { this.myId = m.id; resolve(); }
        else this._handle(m);
      };
      clearInterval(this._ping);
      this._ping = setInterval(() => { if (ws.readyState === 1) ws.send('{"t":"p"}'); }, 20000);
    });
  },

  _lost(msg) {
    this.status(msg);
    this.reset();
    if (this.onLeft) this.onLeft();
  },

  _handle(m) {
    switch (m.t) {
      case "hosted":
        this.myId = m.id; this.hostId = m.id; this.isHost = true; this.inRoom = true;
        this.players = {}; this.players[this.myId] = this.myInfo();
        this.bots = []; this.mode = "tdm"; this.bossLevel = 1;
        this._lobbyChanged(); break;
      case "joined":
        this.myId = m.id; this.hostId = m.host_id; this.isHost = false; this.inRoom = true;
        this.send("host", { k: "hello", info: this.myInfo() }); break;
      case "peer_joined": break; // wait for their hello
      case "peer_left":
        if (this.isHost) { delete this.players[m.id]; this.broadcastLobby(); if (this.onMsg) this.onMsg(m.id, { k: "left" }); }
        break;
      case "closed": this._lost("صاحب الغرفة خرج"); break;
      case "err": this.status(m.msg); break;
      case "r": this.dispatch(m.from, m.m); break;
    }
  },

  // ---- messaging: everything goes through dispatch(), also for the local peer ----
  send(to, m) { // to: "host" | "all" | peer id
    if (to === "host" && this.isHost) { this.dispatch(this.myId, m); return; }
    if (this.ws && this.ws.readyState === 1) this.ws.send(JSON.stringify({ t: "r", to, m }));
  },
  bcast(m) { // host -> everyone including myself
    this.send("all", m);
    this.dispatch(this.myId, m);
  },

  dispatch(from, m) {
    // lobby protocol
    if (m.k === "hello" && this.isHost) {
      m.info.team = this._smallerTeam();
      this.players[from] = m.info;
      this.broadcastLobby();
      return;
    }
    if (m.k === "team" && this.isHost) {
      if (this.players[from] && (m.team === 0 || m.team === 1)) { this.players[from].team = m.team; this.broadcastLobby(); }
      return;
    }
    if (m.k === "lobby") {
      this.players = m.players; this.bots = m.bots; this.mode = m.mode; this.bossLevel = m.bossLevel;
      this.inRoom = true;
      this._lobbyChanged();
      return;
    }
    if (m.k === "start") { this.seed = m.seed; this.inMatch = true; if (this.onStart) this.onStart(); return; }
    if (this.onMsg) this.onMsg(from, m);
  },

  _lobbyChanged() { if (this.onLobby) this.onLobby(); },
  broadcastLobby() {
    const m = { k: "lobby", players: this.players, bots: this.bots, mode: this.mode, bossLevel: this.bossLevel };
    if (!this.solo) this.send("all", m);
    this._lobbyChanged();
  },
  _smallerTeam() {
    const c = [0, 0];
    Object.values(this.players).forEach((p) => c[p.team % 2]++);
    this.bots.forEach((b) => c[b.team % 2]++);
    return c[0] <= c[1] ? 0 : 1;
  },
  teamCount(t) {
    return Object.values(this.players).filter((p) => p.team === t).length + this.bots.filter((b) => b.team === t).length;
  },

  // ---- room actions ----
  async host() {
    await this._open();
    this.solo = false;
    this.ws.send(JSON.stringify({ t: "host" }));
  },
  async join(hostUser) {
    await this._open();
    this.solo = false;
    this.ws.send(JSON.stringify({ t: "join", host: hostUser.toLowerCase() }));
  },
  hostSolo() {
    this.close(true);
    this.solo = true; this.isHost = true; this.inRoom = true; this.myId = 1; this.hostId = 1;
    this.players = { 1: this.myInfo() }; this.bots = []; this.mode = "tdm"; this.bossLevel = 1;
  },
  setTeam(id, team) {
    if (this.isHost) { if (this.players[id]) { this.players[id].team = team; this.broadcastLobby(); } }
    else this.send("host", { k: "team", team });
  },
  addBot(team, level) {
    if (!this.isHost || this.bots.length >= 24) return;
    this.bots.push({ name: BOT_NAMES[this.bots.length % BOT_NAMES.length] + " [Bot]", team, level });
    this.broadcastLobby();
  },
  removeBot(i) { if (this.isHost) { this.bots.splice(i, 1); this.broadcastLobby(); } },
  setBotTeam(i, t) { if (this.isHost && this.bots[i]) { this.bots[i].team = t; this.broadcastLobby(); } },
  setMode(m) { if (this.isHost) { this.mode = m; this.broadcastLobby(); } },
  setBossLevel(l) { if (this.isHost) { this.bossLevel = l; this.broadcastLobby(); } },
  startMatch() {
    if (!this.isHost) return;
    const seed = (Math.random() * 1e9) | 0;
    if (!this.solo) this.broadcastLobby();
    this.bcast({ k: "start", seed });
  },

  close(silent) {
    clearInterval(this._ping);
    if (this.ws) { const w = this.ws; this.ws = null; try { w.close(); } catch (e) {} }
    if (!silent) this.reset();
  },
  reset() {
    this.inRoom = false; this.isHost = false; this.solo = false; this.inMatch = false;
    this.players = {}; this.bots = []; this.mode = "tdm"; this.bossLevel = 1;
  },
  leave() {
    if (this.ws && this.ws.readyState === 1) this.ws.send('{"t":"leave"}');
    this.close();
    if (this.onLeft) this.onLeft();
  },
};
