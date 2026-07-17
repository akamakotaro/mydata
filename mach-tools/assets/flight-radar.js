/* フライトレーダー (マッハーツール版) — フロントエンド
 * OpenSky Network のデータ (api/states.php 経由) を Leaflet 地図に描画する。
 * ダーク/ライトのテーマ切替に対応し、地図タイルもテーマに追従する。
 */

const API_ENDPOINT = window.FR_API_ENDPOINT || "api/states.php";
const REFRESH_MS = 10_000; // 自動更新間隔 (OpenSky 匿名レート制限に配慮)
const THEME_KEY = "mt-flightradar-theme";

// ---- テーマ ---------------------------------------------------------------
const tileLayers = {
  dark: {
    url: "https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png",
    sub: "abcd",
  },
  light: {
    url: "https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png",
    sub: "abcd",
  },
};
const ATTRIB =
  '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> &copy; <a href="https://carto.com/attributions">CARTO</a> · 航空機: <a href="https://opensky-network.org">OpenSky Network</a>';

function currentTheme() {
  return document.documentElement.getAttribute("data-theme") || "dark";
}

// 保存済みテーマを復元
const savedTheme = localStorage.getItem(THEME_KEY);
if (savedTheme === "light" || savedTheme === "dark") {
  document.documentElement.setAttribute("data-theme", savedTheme);
}

// ---- 地図の初期化 ---------------------------------------------------------
const map = L.map("map", { zoomControl: true, worldCopyJump: true }).setView(
  [35.55, 139.9],
  8
); // 初期表示: 東京 (羽田/成田周辺)

let tileLayer = null;
function applyTileLayer() {
  const t = tileLayers[currentTheme()] || tileLayers.dark;
  if (tileLayer) map.removeLayer(tileLayer);
  tileLayer = L.tileLayer(t.url, {
    attribution: ATTRIB,
    subdomains: t.sub,
    maxZoom: 19,
  }).addTo(map);
}
applyTileLayer();

// ---- DOM 参照 -------------------------------------------------------------
const el = {
  status: document.getElementById("status"),
  statusText: document.getElementById("statusText"),
  planeCount: document.getElementById("planeCount"),
  lastUpdate: document.getElementById("lastUpdate"),
  autoRefresh: document.getElementById("autoRefresh"),
  refreshBtn: document.getElementById("refreshBtn"),
  themeBtn: document.getElementById("themeBtn"),
  detail: document.getElementById("detail"),
  detailClose: document.getElementById("detailClose"),
  dCallsign: document.getElementById("dCallsign"),
  dCountry: document.getElementById("dCountry"),
  dAltitude: document.getElementById("dAltitude"),
  dSpeed: document.getElementById("dSpeed"),
  dTrack: document.getElementById("dTrack"),
  dVert: document.getElementById("dVert"),
  dIcao: document.getElementById("dIcao"),
  dSquawk: document.getElementById("dSquawk"),
  dLat: document.getElementById("dLat"),
  dLon: document.getElementById("dLon"),
  dExtLink: document.getElementById("dExtLink"),
};

// テーマ切替ボタン
function syncThemeBtn() {
  if (el.themeBtn) el.themeBtn.textContent = currentTheme() === "dark" ? "🌙" : "☀️";
}
syncThemeBtn();
if (el.themeBtn) {
  el.themeBtn.addEventListener("click", () => {
    const next = currentTheme() === "dark" ? "light" : "dark";
    document.documentElement.setAttribute("data-theme", next);
    localStorage.setItem(THEME_KEY, next);
    applyTileLayer();
    syncThemeBtn();
  });
}

const markers = new Map(); // icao24 -> marker
let selectedIcao = null;
let timer = null;
let inFlight = false;

// ---- アイコン生成 ---------------------------------------------------------
function planeSvg() {
  return `<svg width="26" height="26" viewBox="0 0 24 24" fill="currentColor">
    <path d="M12 2c-.6 0-1 .8-1 1.8V9L3 14v2l8-2.2V19l-2 1.3V22l3-.9 3 .9v-1.7L13 19v-5.2L21 16v-2l-8-5V3.8C13 2.8 12.6 2 12 2z"/>
  </svg>`;
}
function makeIcon(state, selected) {
  const rot = state.trueTrack ?? 0;
  const cls = ["plane-icon", state.onGround ? "ground" : "", selected ? "selected" : ""]
    .filter(Boolean)
    .join(" ");
  return L.divIcon({
    className: "",
    html: `<div class="${cls}" style="transform:rotate(${rot}deg)">${planeSvg()}</div>`,
    iconSize: [26, 26],
    iconAnchor: [13, 13],
  });
}

// ---- 単位変換 -------------------------------------------------------------
const fmt = {
  altitude(m) {
    if (m == null) return "—";
    return `${Math.round(m * 3.28084).toLocaleString()} ft`;
  },
  speed(ms) {
    if (ms == null) return "—";
    return `${Math.round(ms * 1.94384)} kt`;
  },
  track(deg) {
    if (deg == null) return "—";
    const dirs = ["北", "北東", "東", "南東", "南", "南西", "西", "北西"];
    return `${Math.round(deg)}° (${dirs[Math.round(deg / 45) % 8]})`;
  },
  vert(ms) {
    if (ms == null) return "水平飛行";
    const fpm = Math.round(ms * 196.85);
    if (Math.abs(fpm) < 60) return "水平飛行";
    return `${fpm > 0 ? "↑上昇" : "↓降下"} ${Math.abs(fpm).toLocaleString()} ft/min`;
  },
};

// ---- 詳細パネル -----------------------------------------------------------
function showDetail(s) {
  selectedIcao = s.icao24;
  el.dCallsign.textContent = s.callsign || "(コールサインなし)";
  el.dCountry.textContent = s.originCountry || "—";
  el.dAltitude.textContent = fmt.altitude(s.geoAltitude ?? s.baroAltitude);
  el.dSpeed.textContent = fmt.speed(s.velocity);
  el.dTrack.textContent = fmt.track(s.trueTrack);
  el.dVert.textContent = fmt.vert(s.verticalRate);
  el.dIcao.textContent = s.icao24 || "—";
  el.dSquawk.textContent = s.squawk || "—";
  el.dLat.textContent = s.latitude != null ? s.latitude.toFixed(4) : "—";
  el.dLon.textContent = s.longitude != null ? s.longitude.toFixed(4) : "—";
  el.dExtLink.href = `https://opensky-network.org/aircraft-profile?icao24=${s.icao24}`;
  el.detail.classList.remove("hidden");
  refreshSelectionStyles();
}
function hideDetail() {
  el.detail.classList.add("hidden");
  selectedIcao = null;
  refreshSelectionStyles();
}
function refreshSelectionStyles() {
  for (const [icao, m] of markers) m.setIcon(makeIcon(m._state, icao === selectedIcao));
}
el.detailClose.addEventListener("click", hideDetail);

// ---- ステータス -----------------------------------------------------------
function setStatus(kind, text) {
  el.status.className = "fr-status " + kind;
  el.statusText.textContent = text;
}

// ---- データ取得と描画 -----------------------------------------------------
async function fetchAndRender() {
  if (inFlight) return;
  inFlight = true;
  setStatus("loading", "更新中…");

  const b = map.getBounds();
  const params = new URLSearchParams({
    lamin: b.getSouth().toFixed(4),
    lomin: b.getWest().toFixed(4),
    lamax: b.getNorth().toFixed(4),
    lomax: b.getEast().toFixed(4),
  });

  try {
    const res = await fetch(`${API_ENDPOINT}?${params}`);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    render(data.states || []);
    const t = new Date((data.time || Date.now() / 1000) * 1000);
    el.lastUpdate.textContent = `最終更新 ${t.toLocaleTimeString("ja-JP")}`;
    setStatus("ok", data.authenticated ? "接続済み (認証)" : "接続済み");
  } catch (err) {
    console.error(err);
    setStatus("err", "取得に失敗しました");
  } finally {
    inFlight = false;
  }
}

function render(states) {
  const seen = new Set();
  let visible = 0;
  for (const s of states) {
    if (s.latitude == null || s.longitude == null) continue;
    seen.add(s.icao24);
    visible++;
    const selected = s.icao24 === selectedIcao;
    let m = markers.get(s.icao24);
    if (m) {
      m.setLatLng([s.latitude, s.longitude]);
      m.setIcon(makeIcon(s, selected));
      m._state = s;
    } else {
      m = L.marker([s.latitude, s.longitude], { icon: makeIcon(s, selected), riseOnHover: true });
      m._state = s;
      m.bindTooltip(s.callsign || s.icao24, {
        className: "plane-tip",
        direction: "top",
        offset: [0, -12],
      });
      m.on("click", () => showDetail(m._state));
      m.addTo(map);
      markers.set(s.icao24, m);
    }
    if (selected) showDetail(s);
  }
  for (const [icao, m] of markers) {
    if (!seen.has(icao)) {
      map.removeLayer(m);
      markers.delete(icao);
      if (icao === selectedIcao) hideDetail();
    }
  }
  el.planeCount.textContent = visible.toLocaleString();
}

// ---- 自動更新 -------------------------------------------------------------
function startTimer() {
  stopTimer();
  if (el.autoRefresh.checked) timer = setInterval(fetchAndRender, REFRESH_MS);
}
function stopTimer() {
  if (timer) clearInterval(timer);
  timer = null;
}
el.autoRefresh.addEventListener("change", startTimer);
el.refreshBtn.addEventListener("click", fetchAndRender);

let moveTimer = null;
map.on("moveend", () => {
  clearTimeout(moveTimer);
  moveTimer = setTimeout(fetchAndRender, 500);
});

// ---- 起動 -----------------------------------------------------------------
fetchAndRender();
startTimer();
