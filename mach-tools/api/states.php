<?php
/**
 * フライトレーダー用 OpenSky Network プロキシ (マッハーツール版)
 *
 * OpenSky API はブラウザからの直接呼び出しを CORS で許可していないため、
 * サーバー側 (PHP) で中継する。DB は使用せず、一時ファイルで短時間キャッシュし
 * OpenSky の匿名レート制限を緩和する。マッハーツールの「ブラウザ内完結／DB不使用」
 * の方針に沿い、サーバー側では位置データを保存・収集しない。
 *
 * クエリ: ?lamin=&lomin=&lamax=&lomax=  (地図の表示範囲)
 * 応答:   { time, count, states:[{icao24,callsign,...}], authenticated }
 */

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

const OPENSKY_BASE = 'https://opensky-network.org/api/states/all';
const CACHE_TTL    = 6;   // 秒
const HTTP_TIMEOUT = 15;  // 秒

// --- OpenSky OAuth2 (任意) --------------------------------------------------
// 環境変数 OPENSKY_CLIENT_ID / OPENSKY_CLIENT_SECRET を設定すると
// 認証付きで高いレート上限を利用できる。未設定なら匿名で動作する。
function get_access_token(): ?string {
    $id     = getenv('OPENSKY_CLIENT_ID');
    $secret = getenv('OPENSKY_CLIENT_SECRET');
    if (!$id || !$secret) return null;

    $tokenFile = sys_get_temp_dir() . '/opensky_token.json';
    if (is_readable($tokenFile)) {
        $t = json_decode(file_get_contents($tokenFile), true);
        if ($t && ($t['expires_at'] ?? 0) > time() + 30) {
            return $t['token'];
        }
    }

    $url = 'https://auth.opensky-network.org/auth/realms/opensky-network/protocol/openid-connect/token';
    $post = http_build_query([
        'grant_type'    => 'client_credentials',
        'client_id'     => $id,
        'client_secret' => $secret,
    ]);
    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST           => true,
        CURLOPT_POSTFIELDS     => $post,
        CURLOPT_HTTPHEADER     => ['Content-Type: application/x-www-form-urlencoded'],
        CURLOPT_TIMEOUT        => HTTP_TIMEOUT,
    ]);
    $res  = curl_exec($ch);
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    if ($code !== 200 || !$res) return null;

    $json = json_decode($res, true);
    if (empty($json['access_token'])) return null;

    @file_put_contents($tokenFile, json_encode([
        'token'      => $json['access_token'],
        'expires_at' => time() + ($json['expires_in'] ?? 1800),
    ]));
    return $json['access_token'];
}

// --- パラメータ (簡易バリデーション) ---------------------------------------
function num_param(string $k): ?float {
    if (!isset($_GET[$k]) || $_GET[$k] === '') return null;
    if (!is_numeric($_GET[$k])) return null;
    return (float) $_GET[$k];
}

$lamin = num_param('lamin');
$lomin = num_param('lomin');
$lamax = num_param('lamax');
$lomax = num_param('lomax');

$query = [];
$cacheKey = 'all';
if ($lamin !== null && $lomin !== null && $lamax !== null && $lomax !== null) {
    $query = compact('lamin', 'lomin', 'lamax', 'lomax');
    $cacheKey = sprintf('%.2f_%.2f_%.2f_%.2f', $lamin, $lomin, $lamax, $lomax);
}

$cacheFile = sys_get_temp_dir() . '/opensky_' . md5($cacheKey) . '.json';

// --- キャッシュ HIT ---------------------------------------------------------
if (is_readable($cacheFile) && (time() - filemtime($cacheFile) < CACHE_TTL)) {
    header('X-Cache: HIT');
    echo file_get_contents($cacheFile);
    exit;
}

// --- OpenSky から取得 -------------------------------------------------------
$url = OPENSKY_BASE . ($query ? '?' . http_build_query($query) : '');
$headers = ['Accept: application/json'];
$token = get_access_token();
if ($token) $headers[] = 'Authorization: Bearer ' . $token;

$ch = curl_init($url);
curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_HTTPHEADER     => $headers,
    CURLOPT_TIMEOUT        => HTTP_TIMEOUT,
]);
$raw  = curl_exec($ch);
$code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

// 失敗時: 期限切れでもキャッシュがあれば返す (STALE)
if ($code !== 200 || !$raw) {
    if (is_readable($cacheFile)) {
        header('X-Cache: STALE');
        echo file_get_contents($cacheFile);
        exit;
    }
    http_response_code($code ?: 502);
    echo json_encode(['error' => "OpenSky API error: " . ($code ?: 'connection failed')]);
    exit;
}

$data = json_decode($raw, true);
$states = [];
foreach (($data['states'] ?? []) as $s) {
    // OpenSky state ベクトル -> オブジェクト
    // https://openskynetwork.github.io/opensky-api/rest.html
    $states[] = [
        'icao24'        => $s[0],
        'callsign'      => trim($s[1] ?? ''),
        'originCountry' => $s[2],
        'timePosition'  => $s[3],
        'lastContact'   => $s[4],
        'longitude'     => $s[5],
        'latitude'      => $s[6],
        'baroAltitude'  => $s[7],
        'onGround'      => $s[8],
        'velocity'      => $s[9],
        'trueTrack'     => $s[10],
        'verticalRate'  => $s[11],
        'geoAltitude'   => $s[13],
        'squawk'        => $s[14],
        'spi'           => $s[15],
        'positionSource'=> $s[16],
        'category'      => $s[17] ?? null,
    ];
}

$out = json_encode([
    'time'          => $data['time'] ?? time(),
    'count'         => count($states),
    'states'        => $states,
    'authenticated' => (bool) $token,
], JSON_UNESCAPED_UNICODE);

@file_put_contents($cacheFile, $out);
header('X-Cache: MISS');
echo $out;
