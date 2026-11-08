extends Node
# Items, prices and bot/boss levels. Prices must match backend/server.js (SERVER_PRICES).

const TEAM_COLORS := [Color(0.2, 0.55, 1.0), Color(1.0, 0.25, 0.25), Color(0.8, 0.2, 1.0)]
const TEAM_NAMES := ["الفريق الأزرق", "الفريق الأحمر", "البوس"]

const SKINS := {
	"skin_default": {"name": "عادي", "price": 0, "color": Color("e3b48f"), "metal": 0.0, "rough": 0.6, "emit": 0.0},
	"skin_gold": {"name": "ذهبي", "price": 800, "color": Color("ffc83d"), "metal": 1.0, "rough": 0.18, "emit": 0.1},
	"skin_neon": {"name": "نيون", "price": 600, "color": Color("19f0ff"), "metal": 0.2, "rough": 0.3, "emit": 1.6},
	"skin_ghost": {"name": "شبح", "price": 450, "color": Color("d8e4ff"), "metal": 0.0, "rough": 0.2, "emit": 0.7},
	"skin_lava": {"name": "لافا", "price": 700, "color": Color("3a0d05"), "metal": 0.3, "rough": 0.5, "emit": 1.2, "emit_color": Color("ff4a0a")},
	"skin_ice": {"name": "جليد", "price": 500, "color": Color("a8d8ff"), "metal": 0.6, "rough": 0.1, "emit": 0.25},
}

# accessory: "", helmet, headband, cape, visor, cap, hood
const OUTFITS := {
	"outfit_default": {"name": "أساسي", "price": 0, "top": Color("2f6fdc"), "bottom": Color("3b3f4a"), "acc": "", "emit": 0.0},
	"outfit_soldier": {"name": "جندي", "price": 400, "top": Color("4a5d3a"), "bottom": Color("39452d"), "acc": "helmet", "emit": 0.0},
	"outfit_ninja": {"name": "نينجا", "price": 650, "top": Color("16161c"), "bottom": Color("16161c"), "acc": "headband", "emit": 0.0},
	"outfit_knight": {"name": "فارس", "price": 900, "top": Color("aab4c4"), "bottom": Color("8a94a4"), "acc": "cape", "emit": 0.0, "metal": 1.0},
	"outfit_cyber": {"name": "سايبر", "price": 1200, "top": Color("1a1030"), "bottom": Color("120a22"), "acc": "visor", "emit": 1.0, "emit_color": Color("ff2bd6")},
	"outfit_street": {"name": "ستريت", "price": 300, "top": Color("d6342c"), "bottom": Color("2a4a7a"), "acc": "cap", "emit": 0.0},
}

# AI levels: hp, dmg per shot, spread (degrees), fire_rate (sec), speed, reaction (sec), range, turn speed, reward (coins)
const BOT_LEVELS := [
	{"name": "مبتدئ", "hp": 70.0, "dmg": 5.0, "spread": 7.0, "fire_rate": 0.45, "speed": 4.2, "reaction": 0.9, "range": 24.0, "turn": 2.5, "reward": 10},
	{"name": "عادي", "hp": 100.0, "dmg": 7.0, "spread": 4.5, "fire_rate": 0.30, "speed": 5.2, "reaction": 0.6, "range": 30.0, "turn": 3.5, "reward": 20},
	{"name": "محترف", "hp": 130.0, "dmg": 9.0, "spread": 3.0, "fire_rate": 0.20, "speed": 6.0, "reaction": 0.35, "range": 36.0, "turn": 5.0, "reward": 35},
	{"name": "خبير", "hp": 170.0, "dmg": 11.0, "spread": 1.8, "fire_rate": 0.14, "speed": 6.8, "reaction": 0.2, "range": 42.0, "turn": 7.0, "reward": 55},
	{"name": "أسطورة", "hp": 220.0, "dmg": 14.0, "spread": 0.9, "fire_rate": 0.10, "speed": 7.4, "reaction": 0.1, "range": 50.0, "turn": 10.0, "reward": 90},
]

const BOSS_LEVELS := [
	{"name": "البوس 1", "hp": 1500.0, "dmg": 12.0, "spread": 3.5, "fire_rate": 0.22, "speed": 4.0, "reaction": 0.4, "range": 40.0, "turn": 3.0, "slam": 30.0, "reward": 120},
	{"name": "البوس 2", "hp": 2600.0, "dmg": 15.0, "spread": 3.0, "fire_rate": 0.18, "speed": 4.5, "reaction": 0.3, "range": 44.0, "turn": 3.5, "slam": 38.0, "reward": 200},
	{"name": "البوس 3", "hp": 4000.0, "dmg": 19.0, "spread": 2.5, "fire_rate": 0.15, "speed": 5.0, "reaction": 0.25, "range": 48.0, "turn": 4.0, "slam": 46.0, "reward": 300},
	{"name": "البوس 4", "hp": 6000.0, "dmg": 24.0, "spread": 2.0, "fire_rate": 0.12, "speed": 5.4, "reaction": 0.2, "range": 52.0, "turn": 4.5, "slam": 55.0, "reward": 450},
	{"name": "البوس 5", "hp": 9000.0, "dmg": 30.0, "spread": 1.5, "fire_rate": 0.10, "speed": 5.8, "reaction": 0.15, "range": 56.0, "turn": 5.0, "slam": 65.0, "reward": 700},
]

const BOT_NAMES := ["كريم", "ياسمين", "عمر", "نور", "مازن", "سلمى", "هيثم", "دينا", "زياد", "ليلى", "رامي", "هنا"]


func item_name(id: String) -> String:
	if SKINS.has(id):
		return SKINS[id].name
	if OUTFITS.has(id):
		return OUTFITS[id].name
	return id


func item_price(id: String) -> int:
	if SKINS.has(id):
		return SKINS[id].price
	if OUTFITS.has(id):
		return OUTFITS[id].price
	return 0
