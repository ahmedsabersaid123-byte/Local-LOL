// LoCal LoL - account server (no npm packages needed, Node 18+)
// Run:  node server.js        (default port 8080, set PORT to change)
const http = require("http");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const PORT = process.env.PORT || 8080;
const DB_FILE = path.join(__dirname, "db.json");

let db = { users: {}, sessions: {}, rooms: {} };
if (fs.existsSync(DB_FILE)) {
  try { db = Object.assign(db, JSON.parse(fs.readFileSync(DB_FILE, "utf8"))); } catch (e) {}
}
db.sessions = {}; // sessions are not kept across restarts
db.rooms = {};
function save() {
  fs.writeFileSync(DB_FILE, JSON.stringify({ users: db.users }, null, 1));
}

function hashPw(pw, salt) {
  return crypto.scryptSync(pw, salt, 32).toString("hex");
}

const FREE_ITEMS = ["skin_default", "outfit_default", "body_male", "body_female"];

function publicUser(u) {
  return {
    username: u.username,
    display_name: u.display_name,
    coins: u.coins,
    owned: u.owned,
    equipped: u.equipped,
    body: u.body,
    face_b64: u.face_b64 || "",
    level: u.level,
    friends: u.friends,
  };
}

function send(res, code, obj) {
  res.writeHead(code, { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "*", "Access-Control-Allow-Methods": "GET,POST,OPTIONS" });
  res.end(JSON.stringify(obj));
}

function body(req) {
  return new Promise((resolve) => {
    let data = "";
    req.on("data", (c) => { data += c; if (data.length > 3e6) req.destroy(); });
    req.on("end", () => { try { resolve(JSON.parse(data || "{}")); } catch (e) { resolve({}); } });
  });
}

function authUser(b) {
  const name = db.sessions[b.token];
  return name ? db.users[name] : null;
}

const routes = {
  async register(b) {
    const un = String(b.username || "").trim().toLowerCase();
    const pw = String(b.password || "");
    const dn = String(b.display_name || un).trim().slice(0, 16);
    if (!/^[a-z0-9_]{3,16}$/.test(un)) return [400, { error: "اليوزر 3-16 حرف انجليزي أو أرقام أو _" }];
    if (pw.length < 4) return [400, { error: "كلمة السر قصيرة (4 على الأقل)" }];
    if (db.users[un]) return [409, { error: "اليوزر مستخدم" }];
    const salt = crypto.randomBytes(16).toString("hex");
    db.users[un] = {
      username: un, display_name: dn || un, salt, hash: hashPw(pw, salt),
      coins: 500, level: 1, owned: [...FREE_ITEMS],
      equipped: { skin: "skin_default", outfit: "outfit_default" },
      body: "male", face_b64: "", friends: [],
    };
    save();
    const token = crypto.randomBytes(24).toString("hex");
    db.sessions[token] = un;
    return [200, { token, user: publicUser(db.users[un]) }];
  },

  async login(b) {
    const un = String(b.username || "").trim().toLowerCase();
    const u = db.users[un];
    if (!u || hashPw(String(b.password || ""), u.salt) !== u.hash) return [401, { error: "يوزر أو كلمة سر غلط" }];
    const token = crypto.randomBytes(24).toString("hex");
    db.sessions[token] = un;
    return [200, { token, user: publicUser(u) }];
  },

  async me(b) {
    const u = authUser(b);
    if (!u) return [401, { error: "سجل دخول تاني" }];
    return [200, { user: publicUser(u) }];
  },

  async set_name(b) {
    const u = authUser(b);
    if (!u) return [401, { error: "سجل دخول تاني" }];
    u.display_name = String(b.display_name || "").trim().slice(0, 16) || u.display_name;
    save();
    return [200, { user: publicUser(u) }];
  },

  async save_look(b) {
    const u = authUser(b);
    if (!u) return [401, { error: "سجل دخول تاني" }];
    if (b.body === "male" || b.body === "female") u.body = b.body;
    if (typeof b.face_b64 === "string" && b.face_b64.length < 2.5e6) u.face_b64 = b.face_b64;
    for (const slot of ["skin", "outfit"]) {
      const id = b.equipped && b.equipped[slot];
      if (id && u.owned.includes(id)) u.equipped[slot] = id;
    }
    save();
    return [200, { user: publicUser(u) }];
  },

  async buy(b) {
    const u = authUser(b);
    if (!u) return [401, { error: "سجل دخول تاني" }];
    const id = String(b.item || "");
    if (u.owned.includes(id)) return [400, { error: "معاك الحاجة دي" }];
    const price = SERVER_PRICES[id];
    if (price === undefined) return [400, { error: "حاجة غير موجودة" }];
    if (u.coins < price) return [400, { error: "الفلوس مش كفاية" }];
    u.coins -= price;
    u.owned.push(id);
    save();
    return [200, { user: publicUser(u) }];
  },

  async add_coins(b) { // called by the client after a match (small reward, capped)
    const u = authUser(b);
    if (!u) return [401, { error: "سجل دخول تاني" }];
    const amount = Math.max(0, Math.min(800, Number(b.amount) | 0));
    u.coins += amount;
    u.xp = (u.xp || 0) + amount;
    u.level = 1 + Math.floor(u.xp / 200);
    save();
    return [200, { user: publicUser(u) }];
  },

  async search(b) {
    const u = authUser(b);
    if (!u) return [401, { error: "سجل دخول تاني" }];
    const q = String(b.query || "").trim().toLowerCase();
    if (q.length < 2) return [200, { results: [] }];
    const results = Object.values(db.users)
      .filter((x) => x.username !== u.username && x.username.includes(q))
      .slice(0, 20)
      .map((x) => ({ username: x.username, display_name: x.display_name, online: isOnline(x.username), is_friend: u.friends.includes(x.username) }));
    return [200, { results }];
  },

  async add_friend(b) {
    const u = authUser(b);
    if (!u) return [401, { error: "سجل دخول تاني" }];
    const f = db.users[String(b.username || "").toLowerCase()];
    if (!f || f.username === u.username) return [404, { error: "مفيش لاعب بالاسم ده" }];
    if (!u.friends.includes(f.username)) u.friends.push(f.username);
    if (!f.friends.includes(u.username)) f.friends.push(u.username);
    save();
    return [200, { user: publicUser(u) }];
  },

  async friends(b) {
    const u = authUser(b);
    if (!u) return [401, { error: "سجل دخول تاني" }];
    const list = u.friends.map((n) => db.users[n]).filter(Boolean).map((x) => ({
      username: x.username, display_name: x.display_name, online: isOnline(x.username),
      room: roomOf(x.username),
    }));
    return [200, { friends: list }];
  },

  // ---- rooms (host publishes its IP:port so friends can join by username) ----
  async host_room(b) {
    const u = authUser(b);
    if (!u) return [401, { error: "سجل دخول تاني" }];
    db.rooms[u.username] = {
      host: u.username, host_name: u.display_name, ip: b._ip,
      lan_ip: String(b.lan_ip || "").slice(0, 64),
      port: Number(b.port) | 0, players: 1, max: Number(b.max) | 0 || 6, ts: Date.now(),
    };
    return [200, { ok: true }];
  },
  async close_room(b) {
    const u = authUser(b);
    if (!u) return [401, { error: "سجل دخول تاني" }];
    delete db.rooms[u.username];
    return [200, { ok: true }];
  },
  async find_room(b) {
    const u = authUser(b);
    if (!u) return [401, { error: "سجل دخول تاني" }];
    const r = db.rooms[String(b.host || "").toLowerCase()];
    if (!r || Date.now() - r.ts > 120000) return [404, { error: "الغرفة مش موجودة" }];
    return [200, { room: r }];
  },
  async profile(b) {
    const u = authUser(b);
    if (!u) return [401, { error: "سجل دخول تاني" }];
    const x = db.users[String(b.username || "").toLowerCase()];
    if (!x) return [404, { error: "مش موجود" }];
    return [200, { face_b64: x.face_b64 || "" }];
  },
  async heartbeat(b) {
    const u = authUser(b);
    if (!u) return [401, { error: "سجل دخول تاني" }];
    u.last_seen = Date.now();
    if (db.rooms[u.username]) { db.rooms[u.username].ts = Date.now(); db.rooms[u.username].players = Number(b.players) | 1; }
    return [200, { ok: true }];
  },
};

function isOnline(un) { const u = db.users[un]; return !!(u && u.last_seen && Date.now() - u.last_seen < 30000); }
function roomOf(un) { const r = db.rooms[un]; return r && Date.now() - r.ts < 120000 ? r.host : ""; }

// Item prices - keep in sync with scripts/Catalog.gd
const SERVER_PRICES = {
  skin_default: 0, skin_gold: 800, skin_neon: 600, skin_ghost: 450, skin_lava: 700, skin_ice: 500,
  outfit_default: 0, outfit_soldier: 400, outfit_ninja: 650, outfit_knight: 900, outfit_cyber: 1200, outfit_street: 300,
  body_male: 0, body_female: 0,
};

const MIME = { ".html": "text/html; charset=utf-8", ".js": "application/javascript; charset=utf-8", ".css": "text/css; charset=utf-8",
  ".png": "image/png", ".jpg": "image/jpeg", ".svg": "image/svg+xml", ".json": "application/json", ".webmanifest": "application/manifest+json" };
const WEB_DIR = path.join(__dirname, "..", "web");
function serveStatic(name, res) {
  let rel = decodeURIComponent(name || "index.html");
  const file = path.normalize(path.join(WEB_DIR, rel));
  if (!file.startsWith(WEB_DIR) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
    res.writeHead(404); return res.end("not found");
  }
  res.writeHead(200, { "Content-Type": MIME[path.extname(file)] || "application/octet-stream", "Cache-Control": "no-cache" });
  fs.createReadStream(file).pipe(res);
}

const server = http.createServer(async (req, res) => {
  if (req.method === "OPTIONS") return send(res, 204, {});
  const name = req.url.split("?")[0].replace(/^\/+/, "");
  if (name === "ping") return send(res, 200, { ok: true, game: "LoCal LoL" });
  if (req.method === "GET") return serveStatic(name, res);
  const fn = routes[name];
  if (!fn || req.method !== "POST") return send(res, 404, { error: "not found" });
  const b = await body(req);
  const fwd = String(req.headers["x-forwarded-for"] || "").split(",")[0].trim();
  b._ip = (fwd || req.socket.remoteAddress || "").replace("::ffff:", "");
  const [code, out] = await fn(b);
  send(res, code, out);
});
require("./ws")(server, db);
server.listen(PORT, "0.0.0.0", () => console.log("LoCal LoL server on :" + PORT));
