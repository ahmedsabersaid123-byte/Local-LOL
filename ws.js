// Minimal WebSocket relay (no npm packages) used by the browser version.
// The room host (a player's browser) runs the game; this just forwards messages.
const crypto = require("crypto");

module.exports = function attach(server, db) {
  const rooms = {}; // hostUsername -> {user, hostConn, members: Map(id -> conn)}
  let nextId = 1;

  function accept(key) {
    return crypto.createHash("sha1").update(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").digest("base64");
  }

  function send(conn, obj) {
    if (conn.closed) return;
    const data = Buffer.from(JSON.stringify(obj));
    const len = data.length;
    let header;
    if (len < 126) header = Buffer.from([0x81, len]);
    else if (len < 65536) { header = Buffer.alloc(4); header[0] = 0x81; header[1] = 126; header.writeUInt16BE(len, 2); }
    else { header = Buffer.alloc(10); header[0] = 0x81; header[1] = 127; header.writeBigUInt64BE(BigInt(len), 2); }
    try { conn.socket.write(Buffer.concat([header, data])); } catch (e) {}
  }

  function parse(conn, chunk) {
    conn.buf = Buffer.concat([conn.buf, chunk]);
    for (;;) {
      const b = conn.buf;
      if (b.length < 2) return;
      const op = b[0] & 0x0f;
      const masked = !!(b[1] & 0x80);
      let len = b[1] & 0x7f;
      let off = 2;
      if (len === 126) { if (b.length < 4) return; len = b.readUInt16BE(2); off = 4; }
      else if (len === 127) { if (b.length < 10) return; len = Number(b.readBigUInt64BE(2)); off = 10; }
      if (len > 4e6) { conn.socket.destroy(); return; }
      const mlen = masked ? 4 : 0;
      if (b.length < off + mlen + len) return;
      let payload = b.subarray(off + mlen, off + mlen + len);
      if (masked) {
        const mask = b.subarray(off, off + 4);
        payload = Buffer.from(payload);
        for (let i = 0; i < payload.length; i++) payload[i] ^= mask[i & 3];
      }
      conn.buf = b.subarray(off + mlen + len);
      if (op === 8) { conn.socket.end(); return; }
      if (op === 9) { try { conn.socket.write(Buffer.from([0x8a, 0])); } catch (e) {} continue; }
      if (op === 1) {
        let msg;
        try { msg = JSON.parse(payload.toString("utf8")); } catch (e) { continue; }
        onMsg(conn, msg);
      }
    }
  }

  function leave(conn) {
    const room = conn.room;
    if (!room) return;
    conn.room = null;
    room.members.delete(conn.id);
    if (room.hostConn === conn) {
      for (const m of room.members.values()) { send(m, { t: "closed" }); m.room = null; }
      delete rooms[room.user];
      delete db.rooms[room.user];
    } else {
      send(room.hostConn, { t: "peer_left", id: conn.id });
    }
  }

  function onMsg(conn, m) {
    if (m.t === "auth") {
      const un = db.sessions[m.token];
      if (!un) return send(conn, { t: "err", msg: "سجل دخول تاني" });
      conn.user = un;
      return send(conn, { t: "ready", id: conn.id });
    }
    if (!conn.user) return send(conn, { t: "err", msg: "مش مسجل دخول" });
    if (m.t === "p") return;
    if (m.t === "host") {
      leave(conn);
      const u = db.users[conn.user];
      const room = { user: conn.user, hostConn: conn, members: new Map([[conn.id, conn]]) };
      rooms[conn.user] = room;
      conn.room = room;
      db.rooms[conn.user] = { host: conn.user, host_name: u.display_name, ip: "", lan_ip: "", port: 0, players: 1, max: 32, ts: Date.now() };
      return send(conn, { t: "hosted", id: conn.id });
    }
    if (m.t === "join") {
      const room = rooms[String(m.host || "").toLowerCase()];
      if (!room) return send(conn, { t: "err", msg: "الغرفة مش موجودة" });
      if (room.members.size >= 32) return send(conn, { t: "err", msg: "الغرفة مليانة" });
      leave(conn);
      room.members.set(conn.id, conn);
      conn.room = room;
      send(conn, { t: "joined", id: conn.id, host_id: room.hostConn.id });
      return send(room.hostConn, { t: "peer_joined", id: conn.id });
    }
    if (m.t === "leave") return leave(conn);
    if (m.t === "r" && conn.room) {
      const room = conn.room;
      const out = { t: "r", from: conn.id, m: m.m };
      if (m.to === "host") { if (room.hostConn !== conn) send(room.hostConn, out); }
      else if (m.to === "all") { for (const c of room.members.values()) if (c !== conn) send(c, out); }
      else { const c = room.members.get(Number(m.to)); if (c) send(c, out); }
    }
  }

  server.on("upgrade", (req, socket) => {
    if (req.url.split("?")[0] !== "/ws" || !req.headers["sec-websocket-key"]) { socket.destroy(); return; }
    socket.write("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " +
      accept(req.headers["sec-websocket-key"]) + "\r\n\r\n");
    socket.setNoDelay(true);
    const conn = { socket, buf: Buffer.alloc(0), id: nextId++, user: null, room: null, closed: false };
    socket.on("data", (c) => parse(conn, c));
    const close = () => { if (conn.closed) return; leave(conn); conn.closed = true; };
    socket.on("close", close);
    socket.on("error", close);
  });

  setInterval(() => {
    for (const r of Object.values(rooms)) {
      if (db.rooms[r.user]) { db.rooms[r.user].ts = Date.now(); db.rooms[r.user].players = r.members.size; }
    }
  }, 20000);
};
