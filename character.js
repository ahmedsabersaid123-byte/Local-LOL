// Builds the 3D character (Three.js r128): boy/girl body, skin, outfit, your face photo.
// Origin at the feet, facing -Z.
function mat(color, metal, rough, emit, emitColor) {
  return new THREE.MeshStandardMaterial({
    color: color, metalness: metal || 0, roughness: rough == null ? 0.6 : rough,
    emissive: emit > 0 ? (emitColor || color) : "#000000", emissiveIntensity: emit || 0,
  });
}

function capsule(r, len, m, segs) { // vertical capsule centered at origin, total length = len
  const g = new THREE.Group();
  const body = Math.max(len - 2 * r, 0.001);
  const cyl = new THREE.Mesh(new THREE.CylinderGeometry(r, r, body, segs || 14), m);
  const top = new THREE.Mesh(new THREE.SphereGeometry(r, segs || 14, 8), m);
  const bot = top.clone();
  top.position.y = body / 2; bot.position.y = -body / 2;
  [cyl, top, bot].forEach((x) => { x.castShadow = true; g.add(x); });
  return g;
}

function put(parent, obj, x, y, z) { obj.position.set(x, y, z); parent.add(obj); return obj; }
function mesh(geo, m) { const o = new THREE.Mesh(geo, m); o.castShadow = true; return o; }

const _faceCache = {};
function faceTexture(b64) {
  if (_faceCache[b64]) return _faceCache[b64];
  const cv = document.createElement("canvas");
  cv.width = cv.height = 192;
  const tex = new THREE.CanvasTexture(cv);
  tex.encoding = THREE.sRGBEncoding;
  _faceCache[b64] = tex;
  const img = new Image();
  img.onload = () => {
    const c = cv.getContext("2d");
    c.clearRect(0, 0, 192, 192);
    c.drawImage(img, 0, 0, 192, 192);
    c.globalCompositeOperation = "destination-in";
    const g = c.createRadialGradient(96, 96, 60, 96, 96, 96);
    g.addColorStop(0, "rgba(0,0,0,1)"); g.addColorStop(1, "rgba(0,0,0,0)");
    c.fillStyle = g; c.fillRect(0, 0, 192, 192);
    tex.needsUpdate = true;
  };
  img.src = "data:image/jpeg;base64," + b64;
  return tex;
}

function nameSprite(text, color) {
  const cv = document.createElement("canvas");
  cv.width = 512; cv.height = 96;
  const c = cv.getContext("2d");
  c.font = "bold 54px sans-serif"; c.textAlign = "center"; c.textBaseline = "middle";
  c.lineWidth = 10; c.strokeStyle = "rgba(0,0,0,0.85)"; c.strokeText(text, 256, 48);
  c.fillStyle = color || "#fff"; c.fillText(text, 256, 48);
  const t = new THREE.CanvasTexture(cv);
  t.encoding = THREE.sRGBEncoding;
  const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: t, transparent: true, depthWrite: false }));
  s.scale.set(1.9, 0.36, 1);
  return s;
}

function buildCharacter(look, name, teamColor, scale) {
  scale = scale || 1;
  const root = new THREE.Group();   // moved/rotated by the game
  const g = new THREE.Group();      // inner group used for death animation
  root.add(g);
  g.scale.setScalar(scale);

  const female = look.body === "female";
  const skin = SKINS[look.skin] || SKINS.skin_default;
  const outfit = OUTFITS[look.outfit] || OUTFITS.outfit_default;
  const skinM = mat(skin.color, skin.metal, skin.rough, skin.emit, skin.emitColor);
  const topM = mat(outfit.top, outfit.metal || 0, 0.55, outfit.emit, outfit.emitColor);
  const botM = mat(outfit.bottom, outfit.metal || 0, 0.6, 0);
  const shoeM = mat("#1b1b1f", 0.1, 0.5, 0);
  const hairM = mat(female ? "#4a2312" : "#2a1a12", 0, 0.35, 0);
  const gunM = mat("#2b2d33", 0.8, 0.35, 0);

  const hipW = female ? 0.15 : 0.13;
  const shoulder = female ? 0.22 : 0.27;

  function leg(x) {
    const p = new THREE.Group(); p.position.set(x, 0.9, 0); g.add(p);
    put(p, capsule(0.095, 0.86, botM), 0, -0.43, 0);
    put(p, mesh(new THREE.BoxGeometry(0.17, 0.09, 0.3), shoeM), 0, -0.86, -0.05);
    return p;
  }
  const legL = leg(-hipW), legR = leg(hipW);

  const torso = new THREE.Group(); torso.position.set(0, 0.9, 0); g.add(torso);
  const chest = put(torso, capsule(female ? 0.17 : 0.2, 0.75, topM, 18), 0, 0.36, 0);
  chest.scale.set(female ? 1.0 : 1.15, 1, 0.7);
  const belt = put(torso, mesh(new THREE.CylinderGeometry(0.2, 0.2, 0.08, 20), botM), 0, 0.02, 0);
  belt.scale.set(female ? 1.25 : 1.1, 1, 0.75);
  if (female) {
    const skirt = put(torso, mesh(new THREE.CylinderGeometry(0.17, 0.27, 0.22, 20), botM), 0, -0.08, 0);
    skirt.scale.set(1, 1, 0.8);
  }

  function arm(x) {
    const p = new THREE.Group(); p.position.set(x, 0.7, 0); torso.add(p);
    put(p, capsule(0.065, 0.4, topM, 10), 0, -0.2, 0);
    put(p, capsule(0.06, 0.3, skinM, 10), 0, -0.52, 0);
    return p;
  }
  const armL = arm(-shoulder - 0.08), armR = arm(shoulder + 0.08);
  put(armR, mesh(new THREE.BoxGeometry(0.07, 0.55, 0.11), gunM), 0, -0.72, 0);

  put(torso, mesh(new THREE.CylinderGeometry(0.06, 0.06, 0.12, 10), skinM), 0, 0.78, 0);
  const head = new THREE.Group(); head.position.set(0, 0.98, 0); torso.add(head);
  const skull = put(head, mesh(new THREE.SphereGeometry(0.2, 28, 18), skinM), 0, 0, 0);
  skull.scale.set(0.95, 1.08, 1.0);

  const hair = put(head, mesh(new THREE.SphereGeometry(female ? 0.215 : 0.208, 24, 14), hairM), 0, female ? 0.04 : 0.06, 0.05);
  hair.scale.set(0.97, female ? 1.0 : 0.85, 0.98);
  if (female) put(head, capsule(0.07, 0.5, hairM, 8), 0, -0.15, 0.22);

  // accessory
  switch (outfit.acc) {
    case "helmet": put(head, mesh(new THREE.SphereGeometry(0.235, 20, 12), mat(outfit.top, 0.2, 0.5, 0)), 0, 0.07, 0.02).scale.set(1, 0.8, 1.05); break;
    case "headband": put(head, mesh(new THREE.CylinderGeometry(0.212, 0.212, 0.06, 20), mat("#d02020", 0, 0.6, 0)), 0, 0.08, 0); break;
    case "cape": put(torso, mesh(new THREE.BoxGeometry(0.5, 0.95, 0.04), mat("#8a1020", 0, 0.8, 0)), 0, 0.25, 0.2); break;
    case "visor": put(head, mesh(new THREE.BoxGeometry(0.36, 0.07, 0.06), mat("#000", 0, 0.1, 3, outfit.emitColor)), 0, 0.03, -0.17); break;
    case "cap":
      put(head, mesh(new THREE.SphereGeometry(0.215, 20, 12), mat("#d6342c", 0, 0.6, 0)), 0, 0.08, 0.02).scale.set(1, 0.55, 1);
      put(head, mesh(new THREE.BoxGeometry(0.3, 0.02, 0.18), mat("#202228", 0.6, 0.4, 0)), 0, 0.07, -0.2); break;
  }

  // eyes (hidden behind face photo when there is one)
  const eyeM = mat("#101010", 0, 0.3, 0);
  const eyes = new THREE.Group(); head.add(eyes);
  [-1, 1].forEach((s) => put(eyes, mesh(new THREE.SphereGeometry(0.028, 8, 6), eyeM), 0.07 * s, 0.03, -0.185));
  put(eyes, mesh(new THREE.BoxGeometry(0.09, 0.015, 0.02), mat("#7a2a2a", 0, 0.5, 0)), 0, -0.07, -0.185);

  let facePlane = null;
  function setFace(b64) {
    if (facePlane) { head.remove(facePlane); facePlane = null; }
    eyes.visible = !b64;
    if (!b64) return;
    const m = new THREE.MeshStandardMaterial({ map: faceTexture(b64), transparent: true, roughness: 0.55, metalness: 0, depthWrite: false });
    facePlane = new THREE.Mesh(new THREE.PlaneGeometry(0.36, 0.36), m);
    facePlane.position.set(0, 0.0, -0.176);
    facePlane.rotation.y = Math.PI;
    head.add(facePlane);
  }
  setFace(look.face_b64 || "");

  let tag = null;
  if (name) {
    tag = nameSprite(name, teamColor || "#ffffff");
    tag.position.set(0, 2.25 * scale, 0);
    root.add(tag);
  }
  if (teamColor) {
    const ring = new THREE.Mesh(new THREE.RingGeometry(0.45 * scale, 0.62 * scale, 32), new THREE.MeshBasicMaterial({ color: teamColor, side: THREE.DoubleSide }));
    ring.rotation.x = -Math.PI / 2; ring.position.y = 0.03;
    root.add(ring);
  }

  const model = { root, g, legL, legR, armL, armR, torso, head, tag, setFace, t: Math.random() * 6, walk: 0, dying: 0, dead: false, scale };
  return model;
}

function animateCharacter(m, dt, walkTarget, aiming, pitch) {
  m.walk += (walkTarget - m.walk) * Math.min(1, dt * 10);
  if (m.dead) {
    m.dying = Math.min(1, m.dying + dt / 0.45);
    m.g.rotation.x = -Math.PI / 2 * m.dying;
    m.g.position.y = 0.2 * m.dying * m.scale;
    return;
  }
  m.g.rotation.x = 0; m.g.position.y = 0;
  m.t += dt * (3 + m.walk * 7);
  const sw = Math.sin(m.t) * 0.75 * m.walk;
  m.legL.rotation.x = sw; m.legR.rotation.x = -sw;
  m.torso.position.y = 0.9 + Math.abs(Math.sin(m.t)) * 0.02 * m.walk + Math.sin(m.t * 0.5) * 0.02 * (1 - m.walk);
  if (aiming) {
    m.armR.rotation.x = 1.45 + pitch * 0.9;
    m.armL.rotation.x = 1.25 + pitch * 0.9;
    m.armL.rotation.y = -0.35;
    m.torso.rotation.y = -0.15;
    m.head.rotation.x = pitch * 0.6;
  } else {
    m.armL.rotation.x = -sw; m.armR.rotation.x = sw; m.armL.rotation.y = 0; m.torso.rotation.y = 0; m.head.rotation.x = 0;
  }
}

function resetCharacter(m) { m.dead = false; m.dying = 0; }

// ---- rotating preview used in the character + shop tabs (one shared WebGL context) ----
const Preview = {
  r: null, scene: null, cam: null, model: null, host: null, raf: 0, spin: 0,
  _init() {
    if (this.r) return;
    this.r = new THREE.WebGLRenderer({ antialias: true, alpha: true });
    this.r.outputEncoding = THREE.sRGBEncoding;
    this.r.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    this.scene = new THREE.Scene();
    this.cam = new THREE.PerspectiveCamera(38, 1, 0.1, 50);
    this.cam.position.set(0, 1.15, 4.4); this.cam.lookAt(0, 0.95, 0);
    this.scene.add(new THREE.HemisphereLight("#9fb4d8", "#2a3042", 0.9));
    const key = new THREE.DirectionalLight("#ffffff", 1.1); key.position.set(3, 4, 4); this.scene.add(key);
    const rim = new THREE.PointLight("#ff9a1f", 1.4, 12); rim.position.set(-2.5, 2, -2); this.scene.add(rim);
    const base = new THREE.Mesh(new THREE.CylinderGeometry(0.9, 0.95, 0.06, 32), new THREE.MeshStandardMaterial({ color: "#20283d", metalness: 0.6, roughness: 0.3 }));
    base.position.y = -0.03; this.scene.add(base);
  },
  attach(el) {
    this._init();
    this.host = el;
    el.appendChild(this.r.domElement);
    this.r.domElement.style.cssText = "width:100%;height:100%;display:block";
    this._loop();
  },
  detach() { this.host = null; cancelAnimationFrame(this.raf); },
  show(look, name) {
    this._init();
    if (this.model) this.scene.remove(this.model.root);
    this.model = buildCharacter(look, name || "", null, 1);
    this.model.root.rotation.y = this.spin;
    this.scene.add(this.model.root);
  },
  _loop() {
    cancelAnimationFrame(this.raf);
    const tick = () => {
      if (!this.host || !this.host.isConnected) return;
      const w = this.host.clientWidth, h = this.host.clientHeight;
      if (w > 0 && h > 0) {
        if (this.r.domElement.width !== Math.floor(w * this.r.getPixelRatio())) this.r.setSize(w, h, false);
        this.cam.aspect = w / h; this.cam.updateProjectionMatrix();
        if (this.model) {
          this.spin += 0.012; this.model.root.rotation.y = this.spin;
          animateCharacter(this.model, 0.016, 0, false, 0);
        }
        this.r.render(this.scene, this.cam);
      }
      this.raf = requestAnimationFrame(tick);
    };
    this.raf = requestAnimationFrame(tick);
  },
};
