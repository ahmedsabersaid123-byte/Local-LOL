// The 3D arena (Three.js r128). The room host's browser is authoritative for health/kills/bots.
const Match = (() => {
  const G = 24, JUMP = 9.2, HUMAN_SPEED = 6.5, HUMAN_DMG = 14, HUMAN_RATE = 0.11, ARENA = 60;
  const KILL_LIMIT = 25, TDM_TIME = 300, BOSS_TIME = 420;
  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
  const lerp = (a, b, k) => a + (b - a) * k;
  const angDiff = (a, b) => { let d = (b - a) % (Math.PI * 2); if (d > Math.PI) d -= Math.PI * 2; if (d < -Math.PI) d += Math.PI * 2; return d; };
  const lerpAng = (a, b, k) => a + angDiff(a, b) * k;
  function rng32(a) { return () => { a |= 0; a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
  const $ = (id) => document.getElementById(id);

  let renderer, scene, camera, sun, boxes, fighters, local, running, ended, paused;
  let mode, scores, timeLeft, last, sendT, hudT, fxList, rafId, seedRng, touchState, keys, lookQ, mouseDown, locked;
  let tracerGeo, tracerMat, slamGeo;
  let quality = "high";
  const isTouch = () => "ontouchstart" in window || navigator.maxTouchPoints > 0;
  const Q = {
    low: { pr: 1, shadow: 0, lights: false },
    med: { pr: 1.5, shadow: 1024, lights: false },
    high: { pr: 2, shadow: 2048, lights: true },
  };

  // ---------------- world ----------------
  function noiseTexture(base, line) {
    const c = document.createElement("canvas"); c.width = c.height = 256;
    const x = c.getContext("2d");
    x.fillStyle = base; x.fillRect(0, 0, 256, 256);
    for (let i = 0; i < 2600; i++) {
      const v = Math.random();
      x.fillStyle = v < 0.5 ? "rgba(0,0,0,0.07)" : "rgba(255,255,255,0.06)";
      x.fillRect(Math.random() * 256, Math.random() * 256, 1 + Math.random() * 3, 1 + Math.random() * 3);
    }
    if (line) { x.strokeStyle = line; x.lineWidth = 2; x.strokeRect(1, 1, 254, 254); }
    const t = new THREE.CanvasTexture(c);
    t.wrapS = t.wrapT = THREE.RepeatWrapping; t.encoding = THREE.sRGBEncoding;
    t.anisotropy = renderer.capabilities.getMaxAnisotropy();
    return t;
  }

  function boxMesh(sx, sy, sz, m) {
    const geo = new THREE.BoxGeometry(sx, sy, sz);
    const uv = geo.attributes.uv, k = 0.25;
    const dims = [[sz, sy], [sz, sy], [sx, sz], [sx, sz], [sx, sy], [sx, sy]];
    for (let f = 0; f < 6; f++) for (let v = 0; v < 4; v++) {
      const i = f * 4 + v;
      uv.setXY(i, uv.getX(i) * dims[f][0] * k, uv.getY(i) * dims[f][1] * k);
    }
    const o = new THREE.Mesh(geo, m);
    o.castShadow = true; o.receiveShadow = true;
    return o;
  }

  function addBox(cx, cy, cz, sx, sy, sz, m, visual) {
    const o = visual || boxMesh(sx, sy, sz, m);
    o.position.set(cx, cy, cz);
    scene.add(o);
    boxes.push({ minx: cx - sx / 2, maxx: cx + sx / 2, miny: cy - sy / 2, maxy: cy + sy / 2, minz: cz - sz / 2, maxz: cz + sz / 2 });
  }

  function buildWorld(seed) {
    const q = Q[quality];
    scene.fog = new THREE.FogExp2(0xbcd0e4, 0.0042);
    // sky dome
    const sky = new THREE.Mesh(new THREE.SphereGeometry(450, 24, 12), new THREE.ShaderMaterial({
      side: THREE.BackSide, depthWrite: false, fog: false,
      vertexShader: "varying float vy; void main(){ vy = normalize(position).y; gl_Position = projectionMatrix*modelViewMatrix*vec4(position,1.0); }",
      fragmentShader: "varying float vy; void main(){ vec3 top=vec3(0.18,0.42,0.78); vec3 hor=vec3(0.78,0.86,0.94); vec3 c=mix(hor,top,smoothstep(0.0,0.7,vy)); if(vy<0.0) c=mix(hor,vec3(0.5,0.55,0.6),clamp(-vy*3.0,0.0,1.0)); gl_FragColor=vec4(c,1.0);} ",
    }));
    scene.add(sky);

    scene.add(new THREE.HemisphereLight(0xcfe0f5, 0x59606a, 0.85));
    sun = new THREE.DirectionalLight(0xfff2dd, 1.15);
    sun.position.set(-50, 80, 40);
    if (q.shadow) {
      sun.castShadow = true;
      sun.shadow.mapSize.set(q.shadow, q.shadow);
      const c = sun.shadow.camera; c.left = -75; c.right = 75; c.top = 75; c.bottom = -75; c.near = 10; c.far = 220;
      sun.shadow.bias = -0.0006;
      renderer.shadowMap.enabled = true;
      renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    }
    scene.add(sun);

    const groundT = noiseTexture("#80858a", "rgba(0,0,0,0.25)"); groundT.repeat.set(30, 30);
    const ground = new THREE.Mesh(new THREE.PlaneGeometry(ARENA * 2, ARENA * 2), new THREE.MeshStandardMaterial({ map: groundT, roughness: 0.85 }));
    ground.rotation.x = -Math.PI / 2; ground.receiveShadow = true;
    scene.add(ground);

    const tex = noiseTexture("#a3a6a8", "rgba(0,0,0,0.18)");
    const concrete = new THREE.MeshStandardMaterial({ map: tex, roughness: 0.9 });
    const metal = new THREE.MeshStandardMaterial({ map: noiseTexture("#59647a", "rgba(255,255,255,0.15)"), roughness: 0.4, metalness: 0.7 });
    const paint = new THREE.MeshStandardMaterial({ map: noiseTexture("#d9731a", "rgba(0,0,0,0.2)"), roughness: 0.55, metalness: 0.1 });
    const wallM = new THREE.MeshStandardMaterial({ map: noiseTexture("#5c6068", "rgba(0,0,0,0.3)"), roughness: 0.75 });

    const h = 12;
    addBox(0, h / 2, -ARENA - 1, ARENA * 2 + 4, h, 2, wallM);
    addBox(0, h / 2, ARENA + 1, ARENA * 2 + 4, h, 2, wallM);
    addBox(-ARENA - 1, h / 2, 0, 2, h, ARENA * 2, wallM);
    addBox(ARENA + 1, h / 2, 0, 2, h, ARENA * 2, wallM);

    // central platform + stairs on four sides
    addBox(0, 0.6, 0, 14, 1.2, 14, concrete);
    for (const [dx, dz] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
      const alongX = dx !== 0;
      const w = 8;
      addBox(dx * 8, 0.4, dz * 8, alongX ? 2 : w, 0.8, alongX ? w : 2, metal);
      addBox(dx * 10, 0.2, dz * 10, alongX ? 2 : w, 0.4, alongX ? w : 2, metal);
    }

    const r = rng32(seed);
    const mats = [concrete, metal, paint];
    const placed = [];
    let tries = 0;
    while (placed.length < 34 && tries++ < 400) {
      const sx = 3 + r() * 6, sy = 1.6 + r() * 3.4, sz = 3 + r() * 6;
      const px = (r() * 2 - 1) * 50, pz = (r() * 2 - 1) * 34;
      if (Math.hypot(px, pz) < 16) continue;
      let ok = true;
      for (const p of placed) if (Math.abs(px - p.x) < (sx + p.w) / 2 + 3 && Math.abs(pz - p.z) < (sz + p.d) / 2 + 3) { ok = false; break; }
      const m = mats[Math.floor(r() * 3)];
      if (!ok) continue;
      placed.push({ x: px, z: pz, w: sx, d: sz });
      addBox(px, sy / 2, pz, sx, sy, sz, m);
    }
    for (let i = 0; i < 6; i++) {
      const px = (r() * 2 - 1) * 45, pz = (r() * 2 - 1) * 30;
      if (Math.hypot(px, pz) < 15) continue;
      const cyl = new THREE.Mesh(new THREE.CylinderGeometry(1.5, 1.7, 9, 24), metal);
      cyl.castShadow = cyl.receiveShadow = true;
      addBox(px, 4.5, pz, 3.2, 9, 3.2, null, cyl);
    }

    // team bases
    for (let t = 0; t < 2; t++) {
      const z = t === 0 ? -50 : 50;
      const col = new THREE.Color(TEAM_COLORS[t]);
      const pad = new THREE.Mesh(new THREE.BoxGeometry(44, 0.06, 12), new THREE.MeshBasicMaterial({ color: col.clone().multiplyScalar(0.7) }));
      pad.position.set(0, 0.035, z); scene.add(pad);
      if (q.lights) for (const lx of [-18, 18]) {
        const l = new THREE.PointLight(col, 1.2, 40); l.position.set(lx, 6, z); scene.add(l);
      }
    }
  }

  // ---------------- physics ----------------
  function overlaps(f, b) {
    return f.x + f.r > b.minx && f.x - f.r < b.maxx && f.z + f.r > b.minz && f.z - f.r < b.maxz &&
      f.y + f.h > b.miny + 0.01 && f.y < b.maxy - 0.01;
  }
  function moveBody(f, dt) {
    f.vy -= G * dt;
    // X
    f.x += f.vx * dt;
    for (const b of boxes) if (overlaps(f, b)) {
      const step = b.maxy - f.y;
      if (f.onGround && step > 0 && step <= 0.55) f.y = b.maxy;
      else f.x = f.vx > 0 ? b.minx - f.r - 0.001 : b.maxx + f.r + 0.001;
    }
    // Z
    f.z += f.vz * dt;
    for (const b of boxes) if (overlaps(f, b)) {
      const step = b.maxy - f.y;
      if (f.onGround && step > 0 && step <= 0.55) f.y = b.maxy;
      else f.z = f.vz > 0 ? b.minz - f.r - 0.001 : b.maxz + f.r + 0.001;
    }
    // Y
    const prevY = f.y;
    f.y += f.vy * dt;
    f.onGround = false;
    if (f.y <= 0) { f.y = 0; f.vy = 0; f.onGround = true; }
    for (const b of boxes) {
      if (f.x + f.r > b.minx && f.x - f.r < b.maxx && f.z + f.r > b.minz && f.z - f.r < b.maxz && f.y + f.h > b.miny && f.y < b.maxy) {
        if (f.vy <= 0 && prevY >= b.maxy - 0.05) { f.y = b.maxy; f.vy = 0; f.onGround = true; }
        else if (f.vy > 0 && prevY + f.h <= b.miny + 0.05) { f.y = b.miny - f.h - 0.001; f.vy = 0; }
      }
    }
    const lim = ARENA - f.r;
    f.x = clamp(f.x, -lim, lim); f.z = clamp(f.z, -lim, lim);
  }

  function steer(f, dt, sx, fw, jump, sprint) {
    const speed = (f.human ? HUMAN_SPEED : f.cfg.speed) * (sprint ? 1.5 : 1);
    const l = Math.hypot(sx, fw); if (l > 1) { sx /= l; fw /= l; }
    const sn = Math.sin(f.yaw), cs = Math.cos(f.yaw);
    const wx = (cs * sx - sn * fw) * speed, wz = (-sn * sx - cs * fw) * speed;
    const k = clamp(dt * 14, 0, 1);
    f.vx = lerp(f.vx, wx, k); f.vz = lerp(f.vz, wz, k);
    if (f.onGround && jump) { f.vy = JUMP; f.onGround = false; }
    moveBody(f, dt);
    f.moving = Math.hypot(f.vx, f.vz) > 0.6;
  }

  // ---------------- ray tests ----------------
  function rayBox(o, d, b, maxT) {
    let t0 = 0, t1 = maxT;
    const ax = [["x", "minx", "maxx"], ["y", "miny", "maxy"], ["z", "minz", "maxz"]];
    for (const [a, mn, mx] of ax) {
      const dv = d[a], ov = o[a];
      if (Math.abs(dv) < 1e-9) { if (ov < b[mn] || ov > b[mx]) return Infinity; }
      else {
        let ta = (b[mn] - ov) / dv, tb = (b[mx] - ov) / dv;
        if (ta > tb) { const s = ta; ta = tb; tb = s; }
        t0 = Math.max(t0, ta); t1 = Math.min(t1, tb);
        if (t0 > t1) return Infinity;
      }
    }
    return t0;
  }
  function rayBoxes(o, d, maxT) {
    let best = maxT;
    for (const b of boxes) { const t = rayBox(o, d, b, best); if (t < best) best = t; }
    return best;
  }
  function raySphere(o, d, cx, cy, cz, r) {
    const ox = o.x - cx, oy = o.y - cy, oz = o.z - cz;
    const b = ox * d.x + oy * d.y + oz * d.z;
    const c = ox * ox + oy * oy + oz * oz - r * r;
    if (c > 0 && b > 0) return Infinity;
    const disc = b * b - c;
    if (disc < 0) return Infinity;
    return Math.max(0, -b - Math.sqrt(disc));
  }
  function rayFighter(o, d, f, maxT) {
    const s = f.scale;
    const head = raySphere(o, d, f.x, f.y + 1.62 * s, f.z, 0.27 * s);
    const body = Math.min(raySphere(o, d, f.x, f.y + 1.1 * s, f.z, 0.45 * s), raySphere(o, d, f.x, f.y + 0.5 * s, f.z, 0.5 * s));
    if (head <= body && head < maxT) return { t: head, head: true };
    if (body < maxT) return { t: body, head: false };
    return null;
  }
  // nearest thing along the ray: {t, fighter, head}
  function trace(o, d, maxT, team) {
    let t = rayBoxes(o, d, maxT), who = null, head = false;
    for (const f of fighters.values()) {
      if (!f.alive || f.team === team) continue;
      const h = rayFighter(o, d, f, t);
      if (h && h.t < t) { t = h.t; who = f; head = h.head; }
    }
    return { t, fighter: who, head };
  }

  // ---------------- fighters ----------------
  function makeFighter(key, name, team, look, human, cfg, boss, owner, x, z, yaw, username) {
    const s = boss ? 2.2 : 1;
    const f = {
      key, name, team, look, human, cfg, boss, owner, username,
      scale: s, r: 0.38 * s, h: 1.8 * s, x, y: 0, z, vx: 0, vy: 0, vz: 0, yaw, pitch: 0,
      hp: cfg.hp, maxHp: cfg.hp, alive: true, kills: 0, deaths: 0, onGround: true, fireCd: 0, moving: false,
      nx: x, ny: 0, nz: z, nyaw: yaw, npitch: 0,
      ai: { target: null, retarget: 0, react: cfg.reaction || 0.5, strafe: Math.random() < 0.5 ? 1 : -1, strafeT: 1, stuck: 0, slam: 6 },
    };
    f.mine = owner === Net.myId;
    f.model = buildCharacter(look, f.mine && human ? "" : name, TEAM_COLORS[team], s);
    scene.add(f.model.root);
    placeModel(f);
    fighters.set(key, f);
    if (human && !f.mine && username) faceOf(username).then((b) => { if (b) f.model.setFace(b); });
    return f;
  }
  function placeModel(f) { f.model.root.position.set(f.x, f.y, f.z); f.model.root.rotation.y = f.yaw; }

  function spawnPoint(team, idx) {
    if (team === 2) return [0, 40];
    const z = team === 0 ? -50 : 50, inward = team === 0 ? 1 : -1;
    return [-14 + (idx % 8) * 4, z + inward * Math.floor(idx / 8) * 3];
  }
  const yawFor = (team) => (team === 0 ? Math.PI : 0);
  function randomSpawn(team) {
    const z = team === 0 ? -50 : 50, inward = team === 0 ? 3 : -3;
    return [(Math.random() * 2 - 1) * 18, z + inward * Math.random() * 2];
  }

  function spawnAll() {
    const idx = [0, 0, 0];
    const ids = Object.keys(Net.players).map(Number).sort((a, b) => a - b);
    for (const id of ids) {
      const p = Net.players[id];
      const team = mode === "boss" ? 0 : p.team;
      const [x, z] = spawnPoint(team, idx[team]++);
      const look = id === Net.myId ? Api.look() : p.look;
      const f = makeFighter("p" + id, p.name, team, look, true, { hp: 100 }, false, id, x, z, yawFor(team), p.username);
      if (id === Net.myId) local = f;
    }
    const skinIds = ["skin_default", "skin_default", "skin_ice", "skin_neon"], outIds = Object.keys(OUTFITS);
    Net.bots.forEach((b, i) => {
      const team = mode === "boss" ? 0 : b.team;
      const [x, z] = spawnPoint(team, idx[team]++);
      const r = rng32(Net.seed + i * 7919);
      const look = { body: r() < 0.5 ? "female" : "male", skin: skinIds[Math.floor(r() * skinIds.length)], outfit: outIds[Math.floor(r() * outIds.length)], face_b64: "" };
      const lv = clamp(b.level, 1, BOT_LEVELS.length);
      makeFighter("b" + i, b.name, team, look, false, BOT_LEVELS[lv - 1], false, Net.hostId, x, z, yawFor(team));
    });
    if (mode === "boss") {
      const bc = BOSS_LEVELS[clamp(Net.bossLevel, 1, BOSS_LEVELS.length) - 1];
      const [x, z] = spawnPoint(2, 0);
      makeFighter("boss", "👑 " + bc.name, 2, { body: "male", skin: "skin_lava", outfit: "outfit_knight", face_b64: "" }, false, bc, true, Net.hostId, x, z, 0);
    }
  }

  function nearestEnemy(f) {
    let best = null, bd = Infinity;
    for (const o of fighters.values()) {
      if (!o.alive || o.team === f.team) continue;
      const d = (o.x - f.x) ** 2 + (o.z - f.z) ** 2;
      if (d < bd) { bd = d; best = o; }
    }
    return best;
  }

  // ---------------- AI (host only) ----------------
  function aiThink(f, dt) {
    const c = f.cfg, ai = f.ai;
    const it = { sx: 0, fw: 0, jump: false, sprint: false, fire: false };
    ai.retarget -= dt;
    if (ai.retarget <= 0 || !ai.target || !ai.target.alive) {
      ai.retarget = 0.6;
      const nt = nearestEnemy(f);
      if (nt !== ai.target) ai.react = c.reaction;
      ai.target = nt;
    }
    if (f.boss) { ai.slam -= dt; if (ai.slam <= 0) { ai.slam = 7; hostSlam(f); } }
    const t = ai.target;
    if (!t) return it;
    const dx = t.x - f.x, dz = t.z - f.z, dist = Math.hypot(dx, dz);
    const want = Math.atan2(-dx, -dz);
    f.yaw = lerpAng(f.yaw, want, clamp(dt * c.turn, 0, 1));
    const aimDy = (t.y + 1.2 * t.scale) - (f.y + 1.45 * f.scale);
    f.pitch = lerp(f.pitch, clamp(Math.atan2(aimDy, Math.max(dist, 1)), -0.6, 0.6), clamp(dt * 6, 0, 1));
    const rg = c.range;
    let mz = 0;
    if (dist > rg * 0.55) { mz = -1; it.sprint = dist > rg; } else if (dist < rg * 0.22) mz = 1;
    ai.strafeT -= dt;
    if (ai.strafeT <= 0) { ai.strafeT = 0.7 + Math.random() * 1.1; if (Math.random() < 0.5) ai.strafe = -ai.strafe; }
    let mx = dist < rg * 0.9 ? ai.strafe * 0.7 : 0;
    if ((Math.abs(mx) + Math.abs(mz)) > 0.1 && Math.hypot(f.vx, f.vz) < 0.9) ai.stuck += dt; else ai.stuck = Math.max(0, ai.stuck - dt);
    if (ai.stuck > 0.5) { it.jump = true; mx = ai.strafe; if (ai.stuck > 1.1) { ai.strafe = -ai.strafe; ai.stuck = 0; } }
    it.sx = mx; it.fw = -mz;
    const facing = Math.abs(angDiff(f.yaw, want));
    if (dist < rg && facing < 0.22) {
      ai.react -= dt;
      if (ai.react <= 0) {
        const o = { x: f.x, y: f.y + 1.45 * f.scale, z: f.z };
        const e = { x: t.x - o.x, y: t.y + 1.2 * t.scale - o.y, z: t.z - o.z };
        const l = Math.hypot(e.x, e.y, e.z);
        if (rayBoxes(o, { x: e.x / l, y: e.y / l, z: e.z / l }, l) >= l) it.fire = true;
      }
    } else if (dist >= rg || facing >= 0.5) ai.react = c.reaction;
    return it;
  }

  function botShoot(f) {
    const t = f.ai.target; if (!t) return;
    f.fireCd = f.cfg.fire;
    const o = { x: f.x, y: f.y + 1.45 * f.scale, z: f.z };
    let d = { x: t.x - o.x, y: t.y + 1.2 * t.scale - o.y, z: t.z - o.z };
    const l = Math.hypot(d.x, d.y, d.z);
    const sp = Math.tan(f.cfg.spread * Math.PI / 180);
    d = { x: d.x / l + (Math.random() * 2 - 1) * sp, y: d.y / l + (Math.random() * 2 - 1) * sp, z: d.z / l + (Math.random() * 2 - 1) * sp };
    const dl = Math.hypot(d.x, d.y, d.z); d.x /= dl; d.y /= dl; d.z /= dl;
    const h = trace(o, d, 220, f.team);
    const end = { x: o.x + d.x * h.t, y: o.y + d.y * h.t, z: o.z + d.z * h.t };
    const mz = { x: o.x + d.x * 0.8, y: o.y - 0.1, z: o.z + d.z * 0.8 };
    sendFx(mz, end);
    if (h.fighter) hostDamage(h.fighter, f.cfg.dmg * (h.head ? 1.5 : 1), f);
  }

  // ---------------- damage flow ----------------
  function hostDamage(t, dmg, s) {
    if (!Net.isHost || ended || !t.alive || !s.alive || t.team === s.team) return;
    t.hp -= dmg;
    if (t === local) flash();
    Net.bcast({ k: "hp", t: t.key, hp: t.hp });
    if (t.hp <= 0) {
      t.alive = false;
      Net.bcast({ k: "death", t: t.key, s: s.key });
    }
  }
  function hostSlam(b) {
    Net.bcast({ k: "slam", x: b.x, z: b.z });
    for (const f of fighters.values())
      if (f.alive && f.team !== b.team && Math.hypot(f.x - b.x, f.z - b.z) < 9) hostDamage(f, b.cfg.slam, b);
  }

  function applyDeath(t, s) {
    t.alive = false; t.hp = 0; t.deaths++; t.model.dead = true; t.moving = false;
    if (t.model.tag) t.model.tag.visible = false;
    if (s) {
      s.kills++;
      if (mode === "tdm" && s.team < 2 && s.team !== t.team) scores[s.team]++;
    }
    feed((s ? s.name : "؟") + "  ➜  " + t.name, t.team);
    if (t === local) respawnLeft = 4;
    if (Net.isHost) {
      if (mode === "tdm" && (scores[0] >= KILL_LIMIT || scores[1] >= KILL_LIMIT)) { Net.bcast({ k: "end", winner: scores[0] >= scores[1] ? 0 : 1 }); return; }
      if (t.boss) { Net.bcast({ k: "end", winner: 0 }); return; }
      const key = t.key;
      setTimeout(() => {
        if (!running || ended || !fighters.has(key)) return;
        const [x, z] = randomSpawn(t.team);
        Net.bcast({ k: "respawn", t: key, x, z });
      }, 4000);
    }
  }
  let respawnLeft = 0;

  function applyRespawn(f, x, z) {
    f.alive = true; f.hp = f.maxHp; f.x = f.nx = x; f.z = f.nz = z; f.y = f.ny = 0; f.vx = f.vy = f.vz = 0;
    f.ai.target = null; resetCharacter(f.model);
    if (f.model.tag && f !== local) f.model.tag.visible = true;
  }

  // ---------------- network messages ----------------
  function onMsg(from, m) {
    if (!running) return;
    switch (m.k) {
      case "st":
        for (const e of m.f) {
          const f = fighters.get(e[0]);
          if (f && !f.mine) { f.nx = e[1]; f.ny = e[2]; f.nz = e[3]; f.nyaw = e[4]; f.npitch = e[5]; f.moving = !!e[6]; }
        }
        break;
      case "fx": spawnTracer(m.a, m.b); break;
      case "dmg": {
        const t = fighters.get(m.t), s = fighters.get(m.s);
        if (Net.isHost && t && s && s.owner === from && s.human) hostDamage(t, clamp(m.d, 0, 60), s);
        break;
      }
      case "hp": {
        const f = fighters.get(m.t);
        if (f) { if (f === local && m.hp < f.hp) flash(); f.hp = m.hp; }
        break;
      }
      case "death": { const t = fighters.get(m.t); if (t && !(t.alive === false && t.model.dead)) applyDeath(t, fighters.get(m.s)); break; }
      case "respawn": { const f = fighters.get(m.t); if (f) applyRespawn(f, m.x, m.z); break; }
      case "slam": slamFx(m.x, m.z); break;
      case "end": endMatch(m.winner); break;
      case "left": {
        const f = fighters.get("p" + from);
        if (f) { scene.remove(f.model.root); fighters.delete("p" + from); }
        break;
      }
    }
  }

  // ---------------- effects ----------------
  function spawnTracer(a, b) {
    const dx = b.x - a.x, dy = b.y - a.y, dz = b.z - a.z, len = Math.hypot(dx, dy, dz);
    if (len < 0.3) return;
    const m = new THREE.Mesh(tracerGeo, tracerMat);
    m.position.set((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2);
    m.scale.set(1, len, 1);
    m.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), new THREE.Vector3(dx / len, dy / len, dz / len));
    scene.add(m);
    fxList.push({ m, ttl: 0.06 });
  }
  function sendFx(a, b) {
    spawnTracer(a, b);
    Net.send("all", { k: "fx", a: { x: +a.x.toFixed(2), y: +a.y.toFixed(2), z: +a.z.toFixed(2) }, b: { x: +b.x.toFixed(2), y: +b.y.toFixed(2), z: +b.z.toFixed(2) } });
  }
  function slamFx(x, z) {
    const m = new THREE.Mesh(slamGeo, new THREE.MeshBasicMaterial({ color: 0xff5a1a, transparent: true, opacity: 0.8 }));
    m.position.set(x, 0.15, z); scene.add(m);
    fxList.push({ m, ttl: 0.5, total: 0.5, slam: true });
  }
  function flash() {
    const e = $("dmgFlash"); e.style.transition = "none"; e.style.opacity = 0.45;
    requestAnimationFrame(() => { e.style.transition = "opacity .4s"; e.style.opacity = 0; });
  }
  function feed(text, team) {
    const d = document.createElement("div");
    d.textContent = text; d.style.color = TEAM_COLORS[team];
    $("feed").appendChild(d);
    while ($("feed").children.length > 6) $("feed").firstChild.remove();
    setTimeout(() => d.remove(), 5000);
  }
  function hitMarker(head) {
    const e = $("hitMark"); e.style.color = head ? "#ff4040" : "#fff"; e.style.opacity = 1;
    setTimeout(() => (e.style.opacity = 0), 120);
  }

  // ---------------- input ----------------
  function setupInput() {
    keys = {}; lookQ = { x: 0, y: 0 }; mouseDown = false; locked = false;
    touchState = { sx: 0, fw: 0, fire: false, jump: false, ids: {}, joyOrigin: null };
    const canvas = renderer.domElement;
    const kd = (e) => { keys[e.code] = true; if (e.code === "Escape") togglePause(true); if (e.code === "Tab") e.preventDefault(); };
    const ku = (e) => { keys[e.code] = false; };
    const mm = (e) => { if (locked) { lookQ.x += e.movementX; lookQ.y += e.movementY; } };
    const md = (e) => { if (e.button === 0 || e.button === 2) { if (!locked && !paused && !ended) canvas.requestPointerLock(); else mouseDown = true; } };
    const mu = () => { mouseDown = false; };
    const pl = () => {
      locked = document.pointerLockElement === canvas;
      if (!locked && running && !ended && !paused && !isTouch()) togglePause(true);
    };
    const cm = (e) => e.preventDefault();
    document.addEventListener("keydown", kd); document.addEventListener("keyup", ku);
    document.addEventListener("mousemove", mm); canvas.addEventListener("mousedown", md); document.addEventListener("mouseup", mu);
    document.addEventListener("pointerlockchange", pl); canvas.addEventListener("contextmenu", cm);
    const un = [() => { document.removeEventListener("keydown", kd); document.removeEventListener("keyup", ku); document.removeEventListener("mousemove", mm); canvas.removeEventListener("mousedown", md); document.removeEventListener("mouseup", mu); document.removeEventListener("pointerlockchange", pl); canvas.removeEventListener("contextmenu", cm); }];

    if (isTouch()) {
      const layer = $("touchLayer"); layer.style.display = "block";
      const joyBase = $("joyBase"), joyKnob = $("joyKnob");
      const R = 55;
      const start = (e) => {
        if (paused || ended) return;
        for (const t of e.changedTouches) {
          const el = document.elementFromPoint(t.clientX, t.clientY);
          const role = el && el.dataset && el.dataset.btn;
          if (role === "pause") { togglePause(true); continue; }
          if (role === "fire") { touchState.ids[t.identifier] = { role: "fire", x: t.clientX, y: t.clientY }; touchState.fire = true; continue; }
          if (role === "jump") { touchState.ids[t.identifier] = { role: "jump" }; touchState.jump = true; continue; }
          if (t.clientX < window.innerWidth * 0.45 && !Object.values(touchState.ids).some((i) => i.role === "joy")) {
            touchState.ids[t.identifier] = { role: "joy", ox: t.clientX, oy: t.clientY };
            joyBase.style.left = t.clientX - 70 + "px"; joyBase.style.top = t.clientY - 70 + "px"; joyBase.style.bottom = "auto";
            joyBase.classList.add("on"); joyKnob.style.transform = "translate(0,0)";
          } else if (t.clientX >= window.innerWidth * 0.45) touchState.ids[t.identifier] = { role: "look", x: t.clientX, y: t.clientY };
        }
        e.preventDefault();
      };
      const move = (e) => {
        for (const t of e.changedTouches) {
          const i = touchState.ids[t.identifier]; if (!i) continue;
          if (i.role === "joy") {
            let dx = (t.clientX - i.ox) / R, dy = (t.clientY - i.oy) / R;
            const l = Math.hypot(dx, dy); if (l > 1) { dx /= l; dy /= l; }
            touchState.sx = Math.abs(dx) < 0.12 ? 0 : dx; touchState.fw = Math.abs(dy) < 0.12 ? 0 : -dy;
            joyKnob.style.transform = `translate(${dx * R}px,${dy * R}px)`;
          } else if (i.role === "look" || i.role === "fire") {
            const k = i.role === "fire" ? 0.7 : 1;
            lookQ.x += (t.clientX - i.x) * k * 1.6; lookQ.y += (t.clientY - i.y) * k * 1.6; i.x = t.clientX; i.y = t.clientY;
          }
        }
        e.preventDefault();
      };
      const end = (e) => {
        for (const t of e.changedTouches) {
          const i = touchState.ids[t.identifier]; if (!i) continue;
          if (i.role === "joy") { touchState.sx = touchState.fw = 0; joyBase.classList.remove("on"); joyBase.style.left = "30px"; joyBase.style.top = "auto"; joyBase.style.bottom = "30px"; joyKnob.style.transform = "translate(0,0)"; }
          if (i.role === "fire") touchState.fire = false;
          if (i.role === "jump") touchState.jump = false;
          delete touchState.ids[t.identifier];
        }
        e.preventDefault();
      };
      layer.addEventListener("touchstart", start, { passive: false }); layer.addEventListener("touchmove", move, { passive: false });
      layer.addEventListener("touchend", end, { passive: false }); layer.addEventListener("touchcancel", end, { passive: false });
      un.push(() => { layer.style.display = "none"; });
    }
    return () => un.forEach((f) => f());
  }

  function togglePause(on) {
    if (ended) return;
    paused = on === undefined ? !paused : on;
    $("pauseMenu").style.display = paused ? "flex" : "none";
    if (paused && document.pointerLockElement) document.exitPointerLock();
    if (paused) { touchState.sx = touchState.fw = 0; touchState.fire = touchState.jump = false; touchState.ids = {}; }
  }

  // ---------------- main loop ----------------
  const camDir = new THREE.Vector3();
  function updateLocal(dt) {
    const f = local;
    // look
    if (f.alive && !paused && !ended) {
      f.yaw -= lookQ.x * 0.0022; f.pitch = clamp(f.pitch - lookQ.y * 0.0022, -1.2, 1.1);
    }
    lookQ.x = lookQ.y = 0;
    let sx = 0, fw = 0, jump = false, sprint = false, fire = false;
    if (f.alive && !paused && !ended) {
      sx = (keys.KeyD || keys.ArrowRight ? 1 : 0) - (keys.KeyA || keys.ArrowLeft ? 1 : 0);
      fw = (keys.KeyW || keys.ArrowUp ? 1 : 0) - (keys.KeyS || keys.ArrowDown ? 1 : 0);
      jump = !!keys.Space; sprint = !!(keys.ShiftLeft || keys.ShiftRight);
      fire = mouseDown && locked;
      sx += touchState.sx; fw += touchState.fw;
      jump = jump || touchState.jump; fire = fire || touchState.fire;
      if (Math.hypot(touchState.sx, touchState.fw) > 0.92) sprint = true;
    }
    if (f.alive) steer(f, dt, sx, fw, jump, sprint); else { f.vx = f.vz = 0; }
    f.fireCd -= dt;
    if (fire && f.fireCd <= 0 && f.alive) playerShoot();
  }

  function cameraRig() {
    const f = local;
    const s = f.scale;
    const cp = Math.cos(f.pitch), sp = Math.sin(f.pitch);
    camDir.set(-Math.sin(f.yaw) * cp, sp, -Math.cos(f.yaw) * cp);
    const rx = Math.cos(f.yaw), rz = -Math.sin(f.yaw);
    const pivot = { x: f.x + rx * 0.65, y: f.y + 1.55 * s, z: f.z + rz * 0.65 };
    const want = { x: pivot.x - camDir.x * 3.3, y: pivot.y - camDir.y * 3.3 + 0.15, z: pivot.z - camDir.z * 3.3 };
    const d = { x: want.x - pivot.x, y: want.y - pivot.y, z: want.z - pivot.z };
    const l = Math.hypot(d.x, d.y, d.z);
    const dn = { x: d.x / l, y: d.y / l, z: d.z / l };
    let dist = Math.min(l, rayBoxes(pivot, dn, l) - 0.25);
    dist = Math.max(dist, 0.4);
    camera.position.set(pivot.x + dn.x * dist, Math.max(pivot.y + dn.y * dist, 0.2), pivot.z + dn.z * dist);
    camera.rotation.order = "YXZ";
    camera.rotation.set(f.pitch, f.yaw, 0);
  }

  function playerShoot() {
    const f = local;
    f.fireCd = HUMAN_RATE;
    const o = { x: camera.position.x, y: camera.position.y, z: camera.position.z };
    const d = { x: camDir.x, y: camDir.y, z: camDir.z };
    const h = trace(o, d, 220, f.team);
    const end = { x: o.x + d.x * h.t, y: o.y + d.y * h.t, z: o.z + d.z * h.t };
    const rx = Math.cos(f.yaw), rz = -Math.sin(f.yaw);
    const mz = { x: f.x + rx * 0.35 - Math.sin(f.yaw) * 0.8, y: f.y + 1.4 * f.scale, z: f.z + rz * 0.35 - Math.cos(f.yaw) * 0.8 };
    sendFx(mz, end);
    if (h.fighter) {
      hitMarker(h.head);
      Net.send("host", { k: "dmg", t: h.fighter.key, s: f.key, d: HUMAN_DMG * (h.head ? 2 : 1) });
    }
  }

  function frame(now) {
    if (!running) return;
    rafId = requestAnimationFrame(frame);
    const dt = Math.min((now - last) / 1000, 0.05); last = now;

    if (!paused || !Net.solo) {
      // simulate even while "paused" in online rooms (pause only blocks input)
      if (!ended) timeLeft = Math.max(0, timeLeft - dt);
      if (Net.isHost && !ended && timeLeft <= 0) {
        if (mode === "tdm") Net.bcast({ k: "end", winner: scores[0] > scores[1] ? 0 : scores[1] > scores[0] ? 1 : -1 });
        else Net.bcast({ k: "end", winner: 2 });
      }
    }
    if (paused && Net.solo) { renderer.render(scene, camera); return; }

    for (const f of fighters.values()) {
      if (f === local) continue;
      if (f.mine) { // bots/boss on the host
        if (f.alive) {
          const it = aiThink(f, dt);
          steer(f, dt, it.sx, it.fw, it.jump, it.sprint);
          f.fireCd -= dt;
          if (it.fire && f.fireCd <= 0) botShoot(f);
        }
      } else {
        const k = clamp(dt * 14, 0, 1);
        f.x = lerp(f.x, f.nx, k); f.y = lerp(f.y, f.ny, k); f.z = lerp(f.z, f.nz, k);
        f.yaw = lerpAng(f.yaw, f.nyaw, k); f.pitch = lerp(f.pitch, f.npitch, k);
      }
    }
    updateLocal(dt);

    for (const f of fighters.values()) {
      placeModel(f);
      animateCharacter(f.model, dt, f.moving ? 1 : 0, true, f.pitch);
      if (f.model.tag) f.model.tag.position.y = 2.25 * f.scale;
    }
    cameraRig();

    for (let i = fxList.length - 1; i >= 0; i--) {
      const e = fxList[i]; e.ttl -= dt;
      if (e.slam) { const p = 1 - e.ttl / e.total; e.m.scale.set(1 + p * 8, 1, 1 + p * 8); e.m.material.opacity = 0.8 * (1 - p); }
      if (e.ttl <= 0) { scene.remove(e.m); if (e.slam) e.m.material.dispose(); fxList.splice(i, 1); }
    }

    // net state @ 20Hz
    sendT += dt;
    if (sendT >= 0.05 && !Net.solo) {
      sendT = 0;
      const arr = [];
      for (const f of fighters.values()) if (f.mine) arr.push([f.key, +f.x.toFixed(2), +f.y.toFixed(2), +f.z.toFixed(2), +f.yaw.toFixed(3), +f.pitch.toFixed(3), f.moving ? 1 : 0]);
      if (arr.length) Net.send("all", { k: "st", f: arr });
    }

    hudT += dt;
    if (hudT > 0.08) { hudT = 0; updateHud(); }
    renderer.render(scene, camera);
  }

  // ---------------- HUD ----------------
  function updateHud() {
    const s = Math.ceil(timeLeft), clock = Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    $("hudTop").textContent = mode === "tdm" ? `🔵 ${scores[0]}   ⏱ ${clock}   ${scores[1]} 🔴` : `الكل ضد البوس   ⏱ ${clock}`;
    if (local) {
      $("hpFill").style.width = clamp(local.hp / local.maxHp, 0, 1) * 100 + "%";
      $("hpText").textContent = `❤ ${Math.max(0, Math.round(local.hp))}   |   قتلات ${local.kills}`;
      if (!local.alive && !ended) { respawnLeft = Math.max(0, respawnLeft - 0.08); $("centerMsg").textContent = "هتنزل بعد " + Math.ceil(respawnLeft); }
      else $("centerMsg").textContent = "";
    }
    const b = fighters.get("boss");
    $("bossBar").style.display = b ? "block" : "none";
    if (b) { $("bossFill").style.width = clamp(b.hp / b.maxHp, 0, 1) * 100 + "%"; $("bossName").textContent = `${b.name}  (${Math.max(0, Math.round(b.hp))})`; }
    const board = $("board");
    board.style.display = keys && keys.Tab && !ended ? "block" : "none";
    if (board.style.display === "block") {
      let out = "";
      for (const t of mode === "tdm" ? [0, 1] : [0, 2]) {
        out += `<b style="color:${TEAM_COLORS[t]}">${TEAM_NAMES[t]}</b><br>`;
        [...fighters.values()].filter((f) => f.team === t).sort((a, b2) => b2.kills - a.kills)
          .forEach((f) => (out += `${esc(f.name)} &nbsp; ${f.kills} / ${f.deaths}<br>`));
        out += "<br>";
      }
      board.innerHTML = out;
    }
  }

  function endMatch(winner) {
    if (ended) return;
    ended = true; paused = false;
    $("pauseMenu").style.display = "none";
    if (document.pointerLockElement) document.exitPointerLock();
    const myTeam = local ? local.team : 0;
    const tie = winner === -1, win = winner === myTeam;
    let reward = win ? 150 : tie ? 90 : 60;
    if (local) reward += local.kills * 10;
    if (mode === "boss" && win) reward += BOSS_LEVELS[clamp(Net.bossLevel, 1, BOSS_LEVELS.length) - 1].reward;
    reward = Math.min(reward, 800);
    Api.call("add_coins", { amount: reward });
    $("resultText").innerHTML = `${tie ? "تعادل" : win ? "🎉 فزتم!" : "خسرتم"}<br>${mode === "tdm" ? `النتيجة: ${scores[0]} - ${scores[1]}<br>` : ""}+${reward} 🪙`;
    $("resultBox").style.display = "flex";
  }

  // ---------------- lifecycle ----------------
  let unInput = null, onResize = null;
  function start(q) {
    quality = q || "high";
    mode = Net.mode; scores = [0, 0]; timeLeft = mode === "tdm" ? TDM_TIME : BOSS_TIME;
    ended = false; paused = false; running = true; fxList = []; boxes = []; fighters = new Map(); local = null;
    sendT = 0; hudT = 0; respawnLeft = 0;
    const host = $("gameHost");
    renderer = new THREE.WebGLRenderer({ antialias: quality !== "low", powerPreference: "high-performance" });
    renderer.outputEncoding = THREE.sRGBEncoding;
    renderer.toneMapping = THREE.ACESFilmicToneMapping; renderer.toneMappingExposure = 1.0;
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, Q[quality].pr));
    renderer.setSize(window.innerWidth, window.innerHeight);
    host.innerHTML = ""; host.appendChild(renderer.domElement);
    scene = new THREE.Scene();
    camera = new THREE.PerspectiveCamera(78, window.innerWidth / window.innerHeight, 0.05, 700);
    tracerGeo = new THREE.CylinderGeometry(0.015, 0.015, 1, 5);
    tracerMat = new THREE.MeshBasicMaterial({ color: 0xffd24a });
    slamGeo = new THREE.CylinderGeometry(1, 1, 0.25, 32);
    buildWorld(Net.seed);
    spawnAll();
    unInput = setupInput();
    onResize = () => { renderer.setSize(window.innerWidth, window.innerHeight); camera.aspect = window.innerWidth / window.innerHeight; camera.updateProjectionMatrix(); };
    window.addEventListener("resize", onResize);
    Net.onMsg = onMsg;
    $("hud").style.display = "block"; $("resultBox").style.display = "none"; $("pauseMenu").style.display = "none"; $("feed").innerHTML = "";
    $("tipText").style.display = isTouch() ? "none" : "block";
    last = performance.now();
    rafId = requestAnimationFrame(frame);
  }

  function stop() {
    running = false;
    cancelAnimationFrame(rafId);
    if (unInput) unInput();
    if (onResize) window.removeEventListener("resize", onResize);
    if (document.pointerLockElement) document.exitPointerLock();
    $("hud").style.display = "none"; $("resultBox").style.display = "none"; $("pauseMenu").style.display = "none";
    if (renderer) { renderer.dispose(); try { renderer.forceContextLoss(); } catch (e) {} renderer.domElement.remove(); renderer = null; }
    Net.onMsg = null;
  }

  function resume() {
    togglePause(false);
    if (!isTouch() && renderer) { try { renderer.domElement.requestPointerLock(); } catch (e) {} }
  }

  return { start, stop, resume, get running() { return running; } };
})();
