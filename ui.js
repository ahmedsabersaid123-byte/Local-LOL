// Menus: login, hub tabs (play, friends, character, shop, levels) and glue to Match/Net.
(function () {
  const $ = (id) => document.getElementById(id);
  const isTouch = "ontouchstart" in window || navigator.maxTouchPoints > 0;
  const store = {
    get(k, d) { try { return localStorage.getItem(k) ?? d; } catch (e) { return d; } },
    set(k, v) { try { localStorage.setItem(k, v); } catch (e) {} },
  };
  let quality = store.get("lol_q", isTouch ? "med" : "high");
  let tab = "play", friendsTimer = null, pollTimer = null;
  let look = null, shopSel = "", msg = "", playMsg = "", searchRes = null, searchMsg = "", friendsList = [];

  const TABS = [["play", "اللعب"], ["friends", "الأصدقاء"], ["char", "الشخصية"], ["shop", "المتجر"], ["levels", "المستويات"]];

  function show(id) {
    ["login", "hub"].forEach((s) => ($(s).style.display = s === id ? (s === "login" ? "flex" : "block") : "none"));
  }

  // ---------------- login ----------------
  async function submit(endpoint) {
    $("lgMsg").textContent = "لحظة...";
    const res = await Api.call(endpoint, {
      username: $("lgUser").value.trim().toLowerCase(), password: $("lgPass").value, display_name: $("lgName").value.trim(),
    });
    if (res.error) { $("lgMsg").textContent = res.error; return; }
    store.set("lol_user", Api.user.username); store.set("lol_token", Api.token);
    enterHub();
  }

  function enterHub() {
    look = Api.look();
    show("hub");
    refreshBar();
    renderTabs();
    renderTab();
    clearInterval(pollTimer);
    pollTimer = setInterval(() => Api.call("heartbeat", { players: Net.inRoom ? Object.keys(Net.players).length : 0 }), 10000);
    Api.call("heartbeat", {});
  }

  function refreshBar() {
    if (!Api.user) return;
    $("tbName").textContent = Api.user.display_name;
    $("tbLevel").textContent = "مستوى " + Api.user.level;
    $("tbCoins").textContent = "🪙 " + Api.user.coins;
  }

  function renderTabs() {
    $("tabs").innerHTML = TABS.map(([k, n]) => `<button data-tab="${k}" class="${k === tab ? "on" : ""}">${n}</button>`).join("");
  }

  function setTab(t) {
    tab = t; msg = ""; renderTabs(); renderTab();
  }

  function renderTab() {
    clearInterval(friendsTimer);
    Preview.detach();
    const body = $("tabBody");
    if (tab === "play") return renderPlay(body);
    if (tab === "friends") return renderFriends(body);
    if (tab === "char") return renderChar(body);
    if (tab === "shop") return renderShop(body);
    renderLevels(body);
  }

  // ---------------- play / lobby ----------------
  function renderPlay(body) {
    body.innerHTML = `<div class="two">
      <div class="panel col">
        <h2>اعمل غرفة</h2>
        <button class="acc" id="pHost">ابدأ غرفة جديدة</button>
        <hr style="border-color:#26304a;width:100%">
        <h3>ادخل غرفة صاحبك (باليوزر)</h3>
        <input id="pJoinUser" placeholder="يوزر صاحب الغرفة" autocapitalize="off" dir="ltr">
        <button id="pJoin">ادخل</button>
        <div id="pMsg" class="mut"></div>
      </div>
      <div class="panel col" id="lobby"></div></div>`;
    $("pHost").onclick = hostRoom;
    $("pJoin").onclick = () => joinRoom($("pJoinUser").value.trim());
    $("pMsg").textContent = playMsg;
    renderLobby();
  }

  async function hostRoom() {
    if (Net.inRoom) { setPlayMsg("إنت جوه غرفة بالفعل"); return; }
    setPlayMsg("بفتح الغرفة...");
    try { await Net.host(); setPlayMsg("الغرفة شغالة. صحابك يدخلوا بيوزرك: " + Api.user.username); } catch (e) { setPlayMsg("مقدرتش أفتح الغرفة"); }
  }
  async function joinRoom(user) {
    if (!user) return;
    if (Net.inRoom) { setPlayMsg("اخرج من الغرفة الحالية الأول"); return; }
    setPlayMsg("بدخل غرفة " + user + "...");
    try { await Net.join(user); } catch (e) { setPlayMsg("مقدرتش أوصل للسيرفر"); }
  }
  function setPlayMsg(t) { playMsg = t; const e = $("pMsg"); if (e) e.textContent = t; }

  function teamCol(t, host) {
    const myId = Net.myId;
    const players = Object.keys(Net.players).map(Number).sort((a, b) => a - b).filter((id) => Net.players[id].team === t);
    let h = `<div class="team" style="border-color:${TEAM_COLORS[t]};background:${TEAM_COLORS[t]}22">
      <b style="color:${TEAM_COLORS[t]}">${TEAM_NAMES[t]} (${Net.teamCount(t)})</b>`;
    for (const id of players) {
      h += `<div class="row" style="margin-top:6px"><span class="grow">${esc(Net.players[id].name)}${id === myId ? "  (إنت)" : ""}</span>` +
        (host || id === myId ? `<button class="sm" data-mv="${id}" data-to="${1 - t}">↔</button>` : "") + `</div>`;
    }
    Net.bots.forEach((b, i) => {
      if (b.team !== t) return;
      h += `<div class="row mut" style="margin-top:6px"><span class="grow">${esc(b.name)}  Lv${b.level}</span>` +
        (host ? `<button class="sm" data-bmv="${i}" data-to="${1 - t}">↔</button><button class="sm" data-bdel="${i}">✕</button>` : "") + `</div>`;
    });
    return h + "</div>";
  }

  function renderLobby() {
    const el = $("lobby");
    if (!el) return;
    if (!Net.inRoom) { el.innerHTML = `<div class="mut" style="font-size:18px">مفيش غرفة دلوقتي.<br>اعمل غرفة أو ادخل غرفة صاحبك.</div>`; return; }
    const host = Net.isHost;
    let h = `<h2>الغرفة</h2><div class="row"><span>نوع اللعب:</span>`;
    if (host) {
      h += `<select id="lMode"><option value="tdm" ${Net.mode === "tdm" ? "selected" : ""}>فريق ضد فريق</option><option value="boss" ${Net.mode === "boss" ? "selected" : ""}>الكل ضد البوس</option></select>`;
      if (Net.mode === "boss") h += `<select id="lBoss">${BOSS_LEVELS.map((b, i) => `<option value="${i + 1}" ${Net.bossLevel === i + 1 ? "selected" : ""}>${b.name}</option>`).join("")}</select>`;
    } else h += `<b class="coins">${Net.mode === "tdm" ? "فريق ضد فريق" : "الكل ضد البوس (" + BOSS_LEVELS[Net.bossLevel - 1].name + ")"}</b>`;
    h += `</div><div class="two">${teamCol(0, host)}${teamCol(1, host)}</div>`;
    if (host) h += `<div class="row"><span>بوت:</span><select id="lBotLv">${BOT_LEVELS.map((b, i) => `<option value="${i + 1}" ${i === 1 ? "selected" : ""}>Lv${i + 1} ${b.name}</option>`).join("")}</select>
      <button class="sm" id="lAdd0">+ للأزرق</button><button class="sm" id="lAdd1">+ للأحمر</button></div>`;
    h += `<div class="row">` + (host ? `<button class="acc grow" id="lStart">ابدأ اللعب</button>` : `<span class="grow mut">مستني صاحب الغرفة يبدأ...</span>`) +
      `<button id="lLeave">خروج من الغرفة</button></div>`;
    el.innerHTML = h;
    if (host) {
      $("lMode").onchange = (e) => Net.setMode(e.target.value);
      if ($("lBoss")) $("lBoss").onchange = (e) => Net.setBossLevel(+e.target.value);
      $("lAdd0").onclick = () => Net.addBot(0, +$("lBotLv").value);
      $("lAdd1").onclick = () => Net.addBot(1, +$("lBotLv").value);
      $("lStart").onclick = () => Net.startMatch();
    }
    $("lLeave").onclick = () => Net.leave();
    el.querySelectorAll("[data-mv]").forEach((b) => (b.onclick = () => Net.setTeam(+b.dataset.mv, +b.dataset.to)));
    el.querySelectorAll("[data-bmv]").forEach((b) => (b.onclick = () => Net.setBotTeam(+b.dataset.bmv, +b.dataset.to)));
    el.querySelectorAll("[data-bdel]").forEach((b) => (b.onclick = () => Net.removeBot(+b.dataset.bdel)));
  }

  // ---------------- friends ----------------
  function renderFriends(body) {
    body.innerHTML = `<div class="two">
      <div class="panel col"><h2>دوّر على صاحبك باليوزر</h2>
        <div class="row"><input class="grow" id="fQ" placeholder="اكتب جزء من اليوزر" autocapitalize="off" dir="ltr"><button class="acc" id="fGo">بحث</button></div>
        <div id="fMsg" class="mut"></div><div id="fRes"></div></div>
      <div class="panel col"><h2>أصحابي</h2><div id="fList"></div></div></div>`;
    $("fGo").onclick = doSearch;
    $("fQ").onkeydown = (e) => { if (e.key === "Enter") doSearch(); };
    drawSearch();
    loadFriends();
    friendsTimer = setInterval(loadFriends, 8000);
  }
  async function doSearch() {
    const q = $("fQ").value.trim().toLowerCase();
    if (q.length < 2) { searchMsg = "اكتب حرفين على الأقل"; searchRes = null; return drawSearch(); }
    searchMsg = "بدور...";
    drawSearch();
    const r = await Api.call("search", { query: q });
    if (r.error) { searchMsg = r.error; searchRes = null; } else { searchRes = r.results; searchMsg = r.results.length ? "لقيت " + r.results.length : "مفيش حد بالاسم ده"; }
    drawSearch();
  }
  function drawSearch() {
    if (!$("fMsg")) return;
    $("fMsg").textContent = searchMsg;
    $("fRes").innerHTML = (searchRes || []).map((r) => `<div class="item"><span class="grow">${esc(r.display_name)} (@${esc(r.username)})</span>${r.online ? '<span class="ok">● أونلاين</span>' : ""}` +
      (r.is_friend ? '<span class="mut">صاحبك</span>' : `<button class="sm" data-add="${esc(r.username)}">إضافة</button>`) + "</div>").join("");
    $("fRes").querySelectorAll("[data-add]").forEach((b) => (b.onclick = async () => { await Api.call("add_friend", { username: b.dataset.add }); doSearch(); loadFriends(); }));
  }
  async function loadFriends() {
    const r = await Api.call("friends");
    if (r.error || !$("fList")) return;
    friendsList = r.friends;
    $("fList").innerHTML = friendsList.length ? friendsList.map((f) => `<div class="item"><span class="${f.online ? "ok" : "mut"}">●</span><span class="grow">${esc(f.display_name)} (@${esc(f.username)})</span>` +
      (f.room ? `<button class="sm acc" data-room="${esc(f.room)}">ادخل غرفته</button>` : "") + "</div>").join("") : '<div class="mut">لسه مفيش أصحاب - دوّر عليهم باليوزر</div>';
    $("fList").querySelectorAll("[data-room]").forEach((b) => (b.onclick = () => { joinRoom(b.dataset.room); setTab("play"); }));
  }

  // ---------------- character ----------------
  function renderChar(body) {
    look = Object.assign({}, Api.look(), look && look._dirty ? look : {});
    body.innerHTML = `<div class="two"><div class="panel"><div class="preview" id="pv"></div></div>
      <div class="panel col"><h2>شخصيتك</h2>
        <div class="row"><span>الجسم:</span><span class="chips"><button id="bMale">ولد</button><button id="bFemale">بنت</button></span></div>
        <div class="row"><span>الوش:</span><button class="acc" id="faceBtn">اختار صورتك</button><button id="faceClr">شيل الصورة</button>
          <input type="file" id="faceFile" accept="image/*" hidden></div>
        <h3>السكنات (اللي معاك)</h3><div class="chips" id="skinChips"></div>
        <h3>اللبسات (اللي معاك)</h3><div class="chips" id="outChips"></div>
        <button class="acc" id="saveLook">حفظ الشخصية</button><div id="cMsg" class="mut"></div></div></div>`;
    Preview.attach($("pv"));
    const draw = () => {
      $("bMale").classList.toggle("on", look.body === "male"); $("bFemale").classList.toggle("on", look.body === "female");
      $("skinChips").innerHTML = Object.keys(SKINS).filter((i) => Api.owned(i)).map((i) => `<button data-skin="${i}" class="${look.skin === i ? "on" : ""}">${SKINS[i].name}</button>`).join("");
      $("outChips").innerHTML = Object.keys(OUTFITS).filter((i) => Api.owned(i)).map((i) => `<button data-out="${i}" class="${look.outfit === i ? "on" : ""}">${OUTFITS[i].name}</button>`).join("");
      $("skinChips").querySelectorAll("button").forEach((b) => (b.onclick = () => { look.skin = b.dataset.skin; look._dirty = 1; draw(); }));
      $("outChips").querySelectorAll("button").forEach((b) => (b.onclick = () => { look.outfit = b.dataset.out; look._dirty = 1; draw(); }));
      Preview.show(look, Api.user.display_name);
    };
    $("bMale").onclick = () => { look.body = "male"; look._dirty = 1; draw(); };
    $("bFemale").onclick = () => { look.body = "female"; look._dirty = 1; draw(); };
    $("faceBtn").onclick = () => $("faceFile").click();
    $("faceClr").onclick = () => { look.face_b64 = ""; look._dirty = 1; draw(); };
    $("faceFile").onchange = (e) => {
      const file = e.target.files[0]; if (!file) return;
      const url = URL.createObjectURL(file), img = new Image();
      img.onload = () => {
        const s = Math.min(img.width, img.height), c = document.createElement("canvas");
        c.width = c.height = 192;
        c.getContext("2d").drawImage(img, (img.width - s) / 2, (img.height - s) / 2, s, s, 0, 0, 192, 192);
        look.face_b64 = c.toDataURL("image/jpeg", 0.88).split(",")[1]; look._dirty = 1;
        URL.revokeObjectURL(url);
        $("cMsg").textContent = "الصورة اتحطت على وشك. اضغط حفظ.";
        draw();
      };
      img.onerror = () => ($("cMsg").textContent = "مقدرتش أفتح الصورة");
      img.src = url;
    };
    $("saveLook").onclick = async () => {
      $("cMsg").textContent = "بحفظ...";
      const r = await Api.call("save_look", { body: look.body, face_b64: look.face_b64, equipped: { skin: look.skin, outfit: look.outfit } });
      $("cMsg").textContent = r.error || "اتحفظت ✔";
      if (!r.error) { look = Api.look(); }
    };
    draw();
  }

  // ---------------- shop ----------------
  function renderShop(body) {
    body.innerHTML = `<div class="two"><div class="panel"><div class="preview" id="pv"></div></div>
      <div class="panel col"><h2>المتجر</h2><div class="coins" id="sCoins"></div><div id="sList" style="max-height:42vh;overflow:auto"></div>
      <button class="acc" id="sAct" disabled></button><div id="sMsg" class="mut"></div></div></div>`;
    Preview.attach($("pv"));
    drawShop();
    Preview.show(Api.look(), Api.user.display_name);
  }
  function drawShop() {
    if (!$("sList")) return;
    $("sCoins").textContent = "فلوسك: 🪙 " + Api.user.coins;
    const ids = [...Object.keys(SKINS).filter((i) => i !== "skin_default").map((i) => [i, "سكن"]), ...Object.keys(OUTFITS).filter((i) => i !== "outfit_default").map((i) => [i, "لبس"])];
    $("sList").innerHTML = ids.map(([id, kind]) => {
      const owned = Api.owned(id), worn = Api.equipped("skin") === id || Api.equipped("outfit") === id;
      return `<div class="item ${shopSel === id ? "sel" : ""}" data-id="${id}"><span class="grow">${kind}: ${itemName(id)}</span><span class="${owned ? "ok" : "coins"}">${owned ? "✔ معاك" + (worn ? " (لابسه)" : "") : "🪙 " + itemPrice(id)}</span></div>`;
    }).join("");
    $("sList").querySelectorAll(".item").forEach((e) => (e.onclick = () => {
      shopSel = e.dataset.id;
      const lk = Api.look();
      if (SKINS[shopSel]) lk.skin = shopSel; else lk.outfit = shopSel;
      Preview.show(lk, Api.user.display_name);
      drawShop();
    }));
    const b = $("sAct");
    if (!shopSel) { b.disabled = true; b.textContent = "اختار حاجة"; return; }
    const slot = SKINS[shopSel] ? "skin" : "outfit";
    if (Api.owned(shopSel)) { b.textContent = Api.equipped(slot) === shopSel ? "لابسه دلوقتي" : "البسه"; b.disabled = Api.equipped(slot) === shopSel; }
    else { b.textContent = "اشتري بـ " + itemPrice(shopSel); b.disabled = Api.user.coins < itemPrice(shopSel); }
    b.onclick = async () => {
      if (!Api.owned(shopSel)) {
        const r = await Api.call("buy", { item: shopSel });
        if (r.error) { $("sMsg").textContent = r.error; return; }
        $("sMsg").textContent = "اشتريت " + itemName(shopSel) + " ✔";
      }
      const eq = { skin: Api.equipped("skin"), outfit: Api.equipped("outfit") };
      eq[SKINS[shopSel] ? "skin" : "outfit"] = shopSel;
      await Api.call("save_look", { body: Api.user.body, face_b64: Api.user.face_b64 || "", equipped: eq });
      refreshBar(); drawShop();
    };
  }

  // ---------------- levels + solo ----------------
  function lvTable(title, levels, boss) {
    return `<div class="panel"><h2>${title}</h2><div style="overflow-x:auto"><table><tr><th>المستوى</th><th>الصحة</th><th>الضرر</th><th>الدقة</th><th>السرعة</th><th>المكافأة</th></tr>` +
      levels.map((l, i) => `<tr><td ${boss ? 'class="coins"' : ""}>${i + 1} ${l.name}</td><td>${l.hp}</td><td>${l.dmg}</td><td>${Math.max(10, Math.min(99, Math.round(100 - l.spread * 8)))}%</td><td>${l.speed.toFixed(1)}</td><td class="coins">🪙 ${l.reward}</td></tr>`).join("") +
      `</table></div>${boss ? '<div class="mut" style="margin-top:6px">البوس بيعمل ضربة أرضية قوية كل 7 ثواني - اتفرقوا!</div>' : ""}</div>`;
  }
  function renderLevels(body) {
    body.innerHTML = `<div class="two">${lvTable("مستويات البوتات", BOT_LEVELS, false)}${lvTable("مستويات البوس", BOSS_LEVELS, true)}</div>
      <div class="panel col" style="margin-top:12px"><h2>تدريب فردي (من غير غرفة)</h2>
        <div class="row"><span>مستوى البوتات:</span><select id="sBot">${BOT_LEVELS.map((b, i) => `<option value="${i + 1}" ${i === 1 ? "selected" : ""}>Lv${i + 1} ${b.name}</option>`).join("")}</select>
          <button class="acc" id="sTdm">ابدأ: أنا وبوتين ضد 3 بوتات</button></div>
        <div class="row"><span>مستوى البوس:</span><select id="sBoss">${BOSS_LEVELS.map((b, i) => `<option value="${i + 1}">${b.name}</option>`).join("")}</select>
          <button class="acc" id="sBossGo">ابدأ: أنا و3 بوتات ضد البوس</button></div>
        <div id="lvMsg" class="err"></div></div>`;
    $("sTdm").onclick = () => {
      if (Net.inRoom) { $("lvMsg").textContent = "اخرج من الغرفة الحالية الأول"; return; }
      Net.hostSolo(); const lv = +$("sBot").value;
      Net.mode = "tdm"; Net.addBot(0, lv); Net.addBot(0, lv); Net.addBot(1, lv); Net.addBot(1, lv); Net.addBot(1, lv);
      Net.startMatch();
    };
    $("sBossGo").onclick = () => {
      if (Net.inRoom) { $("lvMsg").textContent = "اخرج من الغرفة الحالية الأول"; return; }
      Net.hostSolo(); Net.mode = "boss"; Net.bossLevel = +$("sBoss").value;
      for (let i = 0; i < 3; i++) Net.addBot(0, 2);
      Net.startMatch();
    };
  }

  // ---------------- game glue ----------------
  async function goFullscreen() {
    try {
      const el = document.documentElement;
      if (!document.fullscreenElement && el.requestFullscreen) await el.requestFullscreen();
      if (screen.orientation && screen.orientation.lock) await screen.orientation.lock("landscape");
    } catch (e) {}
  }

  Net.onStart = () => {
    clearInterval(friendsTimer); Preview.detach();
    $("hub").style.display = "none"; $("gameHost").style.display = "block";
    document.body.classList.add("ingame"); if (isTouch) document.body.classList.add("touch");
    if (isTouch) goFullscreen();
    Match.start(quality);
  };
  function backToHub() {
    Match.stop();
    $("gameHost").style.display = "none";
    document.body.classList.remove("ingame");
    Net.inMatch = false;
    if (Net.solo) Net.reset();
    Api.call("me").then(() => { refreshBar(); });
    enterHub();
    setTab("play");
  }
  Net.onLobby = () => { if (!Match.running) renderLobby(); };
  Net.onStatus = (t) => setPlayMsg(t);
  Net.onLeft = () => { if (Match.running) backToHub(); else if (tab === "play") renderLobby(); };

  // ---------------- wiring ----------------
  $("btnLogin").onclick = () => submit("login");
  $("btnReg").onclick = () => submit("register");
  $("lgPass").onkeydown = (e) => { if (e.key === "Enter") submit("login"); };
  $("tabs").onclick = (e) => { const b = e.target.closest("[data-tab]"); if (b) setTab(b.dataset.tab); };
  $("qSel").value = quality;
  $("qSel").onchange = (e) => { quality = e.target.value; store.set("lol_q", quality); };
  $("btnFull").onclick = goFullscreen;
  $("btnOut").onclick = async () => {
    if (Net.inRoom) Net.leave();
    store.set("lol_token", ""); Api.token = ""; Api.user = null;
    clearInterval(pollTimer); show("login");
  };
  $("btnResume").onclick = () => Match.resume();
  $("btnLeaveMatch").onclick = () => { Net.leave(); };
  $("btnBack").onclick = backToHub;
  Api.onUser = refreshBar;

  // keep the top bar in sync whenever the account changes (coins, level)
  const origCall = Api.call.bind(Api);
  Api.call = async function (ep, d) { const r = await origCall(ep, d); if (r && r.user) { refreshBar(); if (tab === "shop") drawShop(); } return r; };

  // ---------------- start ----------------
  $("lgUser").value = store.get("lol_user", "");
  (async function init() {
    const tok = store.get("lol_token", "");
    if (tok) {
      Api.token = tok;
      const r = await Api.call("me");
      if (r.user) return enterHub();
      Api.token = "";
    }
    show("login");
  })();
})();
