import express from "express";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const app = express();
const PORT = process.env.PORT || 3000;

const OPENSKY_BASE = "https://opensky-network.org/api";

// --- 簡易キャッシュ (OpenSky のレート制限対策) ---------------------------------
// bbox ごとに短時間キャッシュし、同じ範囲への連続リクエストで API を叩きすぎない。
const cache = new Map(); // key -> { at:number, data:object }
const CACHE_TTL_MS = 6000;

// OpenSky OAuth2 (任意). 認証すると匿名より高いレート上限が使える。
// 環境変数 OPENSKY_CLIENT_ID / OPENSKY_CLIENT_SECRET を設定すると自動で利用。
let tokenCache = { token: null, expiresAt: 0 };

async function getAccessToken() {
  const id = process.env.OPENSKY_CLIENT_ID;
  const secret = process.env.OPENSKY_CLIENT_SECRET;
  if (!id || !secret) return null;

  if (tokenCache.token && Date.now() < tokenCache.expiresAt - 30_000) {
    return tokenCache.token;
  }

  const url =
    "https://auth.opensky-network.org/auth/realms/opensky-network/protocol/openid-connect/token";
  const body = new URLSearchParams({
    grant_type: "client_credentials",
    client_id: id,
    client_secret: secret,
  });

  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });
  if (!res.ok) {
    console.warn("[opensky] token 取得に失敗:", res.status);
    return null;
  }
  const json = await res.json();
  tokenCache = {
    token: json.access_token,
    expiresAt: Date.now() + (json.expires_in ?? 1800) * 1000,
  };
  return tokenCache.token;
}

// OpenSky の state ベクトル配列を扱いやすいオブジェクトに変換する。
// https://openskynetwork.github.io/opensky-api/rest.html
function mapState(s) {
  return {
    icao24: s[0],
    callsign: (s[1] || "").trim(),
    originCountry: s[2],
    timePosition: s[3],
    lastContact: s[4],
    longitude: s[5],
    latitude: s[6],
    baroAltitude: s[7], // m
    onGround: s[8],
    velocity: s[9], // m/s
    trueTrack: s[10], // deg (0 = 北)
    verticalRate: s[11], // m/s
    geoAltitude: s[13], // m
    squawk: s[14],
    spi: s[15],
    positionSource: s[16],
    category: s[17],
  };
}

app.get("/api/states", async (req, res) => {
  const { lamin, lomin, lamax, lomax } = req.query;

  const params = new URLSearchParams();
  let cacheKey = "all";
  if (lamin && lomin && lamax && lomax) {
    params.set("lamin", lamin);
    params.set("lomin", lomin);
    params.set("lamax", lamax);
    params.set("lomax", lomax);
    cacheKey = `${(+lamin).toFixed(2)},${(+lomin).toFixed(2)},${(+lamax).toFixed(
      2
    )},${(+lomax).toFixed(2)}`;
  }

  const cached = cache.get(cacheKey);
  if (cached && Date.now() - cached.at < CACHE_TTL_MS) {
    res.set("X-Cache", "HIT");
    return res.json(cached.data);
  }

  try {
    const token = await getAccessToken();
    const headers = {};
    if (token) headers.Authorization = `Bearer ${token}`;

    const url = `${OPENSKY_BASE}/states/all${
      params.toString() ? "?" + params.toString() : ""
    }`;
    const upstream = await fetch(url, { headers });

    if (!upstream.ok) {
      // レート制限などで失敗した場合、期限切れでもキャッシュがあれば返す
      if (cached) {
        res.set("X-Cache", "STALE");
        return res.json(cached.data);
      }
      return res
        .status(upstream.status)
        .json({ error: `OpenSky API error: ${upstream.status}` });
    }

    const raw = await upstream.json();
    const data = {
      time: raw.time,
      count: Array.isArray(raw.states) ? raw.states.length : 0,
      states: Array.isArray(raw.states) ? raw.states.map(mapState) : [],
      authenticated: Boolean(token),
    };

    cache.set(cacheKey, { at: Date.now(), data });
    res.set("X-Cache", "MISS");
    res.json(data);
  } catch (err) {
    console.error("[api/states] error:", err);
    if (cached) {
      res.set("X-Cache", "STALE");
      return res.json(cached.data);
    }
    res.status(502).json({ error: "上流APIへの接続に失敗しました" });
  }
});

app.get("/api/health", (_req, res) => res.json({ ok: true }));

app.use(express.static(path.join(__dirname, "public")));

app.listen(PORT, () => {
  console.log(`✈  Flight radar app: http://localhost:${PORT}`);
});
