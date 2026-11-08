// Items, prices, bot/boss levels. Prices must match backend/server.js (SERVER_PRICES).
const TEAM_COLORS = ["#3a8cff", "#ff4040", "#c534ff"];
const TEAM_NAMES = ["الفريق الأزرق", "الفريق الأحمر", "البوس"];

const SKINS = {
  skin_default: { name: "عادي", price: 0, color: "#e3b48f", metal: 0.0, rough: 0.6, emit: 0.0 },
  skin_gold: { name: "ذهبي", price: 800, color: "#ffc83d", metal: 1.0, rough: 0.25, emit: 0.15 },
  skin_neon: { name: "نيون", price: 600, color: "#19f0ff", metal: 0.2, rough: 0.3, emit: 0.9 },
  skin_ghost: { name: "شبح", price: 450, color: "#d8e4ff", metal: 0.0, rough: 0.2, emit: 0.5 },
  skin_lava: { name: "لافا", price: 700, color: "#3a0d05", metal: 0.3, rough: 0.5, emit: 1.0, emitColor: "#ff4a0a" },
  skin_ice: { name: "جليد", price: 500, color: "#a8d8ff", metal: 0.6, rough: 0.15, emit: 0.2 },
};

const OUTFITS = {
  outfit_default: { name: "أساسي", price: 0, top: "#2f6fdc", bottom: "#3b4148", acc: "", emit: 0 },
  outfit_soldier: { name: "جندي", price: 400, top: "#4a5d3a", bottom: "#39452d", acc: "helmet", emit: 0 },
  outfit_ninja: { name: "نينجا", price: 650, top: "#16161c", bottom: "#16161c", acc: "headband", emit: 0 },
  outfit_knight: { name: "فارس", price: 900, top: "#aab4c4", bottom: "#8a94a4", acc: "cape", emit: 0, metal: 0.9 },
  outfit_cyber: { name: "سايبر", price: 1200, top: "#1a1030", bottom: "#120a22", acc: "visor", emit: 0.8, emitColor: "#ff2bd6" },
  outfit_street: { name: "ستريت", price: 300, top: "#d6342c", bottom: "#2a4a7a", acc: "cap", emit: 0 },
};

// hp, dmg per shot, spread (deg), fire_rate (sec), speed, reaction (sec), range, turn speed, reward
const BOT_LEVELS = [
  { name: "مبتدئ", hp: 70, dmg: 5, spread: 7.0, fire: 0.45, speed: 4.2, reaction: 0.9, range: 24, turn: 2.5, reward: 10 },
  { name: "عادي", hp: 100, dmg: 7, spread: 4.5, fire: 0.30, speed: 5.2, reaction: 0.6, range: 30, turn: 3.5, reward: 20 },
  { name: "محترف", hp: 130, dmg: 9, spread: 3.0, fire: 0.20, speed: 6.0, reaction: 0.35, range: 36, turn: 5.0, reward: 35 },
  { name: "خبير", hp: 170, dmg: 11, spread: 1.8, fire: 0.14, speed: 6.8, reaction: 0.2, range: 42, turn: 7.0, reward: 55 },
  { name: "أسطورة", hp: 220, dmg: 14, spread: 0.9, fire: 0.10, speed: 7.4, reaction: 0.1, range: 50, turn: 10.0, reward: 90 },
];

const BOSS_LEVELS = [
  { name: "البوس 1", hp: 1500, dmg: 12, spread: 3.5, fire: 0.22, speed: 4.0, reaction: 0.4, range: 40, turn: 3.0, slam: 30, reward: 120 },
  { name: "البوس 2", hp: 2600, dmg: 15, spread: 3.0, fire: 0.18, speed: 4.5, reaction: 0.3, range: 44, turn: 3.5, slam: 38, reward: 200 },
  { name: "البوس 3", hp: 4000, dmg: 19, spread: 2.5, fire: 0.15, speed: 5.0, reaction: 0.25, range: 48, turn: 4.0, slam: 46, reward: 300 },
  { name: "البوس 4", hp: 6000, dmg: 24, spread: 2.0, fire: 0.12, speed: 5.4, reaction: 0.2, range: 52, turn: 4.5, slam: 55, reward: 450 },
  { name: "البوس 5", hp: 9000, dmg: 30, spread: 1.5, fire: 0.10, speed: 5.8, reaction: 0.15, range: 56, turn: 5.0, slam: 65, reward: 700 },
];

const BOT_NAMES = ["كريم", "ياسمين", "عمر", "نور", "مازن", "سلمى", "هيثم", "دينا", "زياد", "ليلى", "رامي", "هنا"];

function itemName(id) { return (SKINS[id] || OUTFITS[id] || { name: id }).name; }
function itemPrice(id) { return (SKINS[id] || OUTFITS[id] || { price: 0 }).price; }
function esc(s) { return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c])); }
