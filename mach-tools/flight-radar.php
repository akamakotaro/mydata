<?php
/**
 * フライトレーダー — マッハーツール ツールページ
 *
 * OpenSky Network のオープンデータで、いま飛んでいる航空機を地図にリアルタイム表示。
 * 登録不要・ブラウザで完結（航空機データの中継のみ api/states.php を経由）。
 *
 * 既存のマッハーツールに組み込む場合は、共通ヘッダー/フッターの include に
 * 差し替えてください（下部の <!-- MACH:HEADER --> / <!-- MACH:FOOTER --> 目印）。
 */
$TOOL_TITLE = 'フライトレーダー｜リアルタイム航空機マップ';
$TOOL_DESC  = 'いま日本や世界の上空を飛んでいる航空機を、地図上にリアルタイム表示。便名・高度・速度・進行方向がわかる無料ツール。登録不要。';
?>
<!DOCTYPE html>
<html lang="ja" data-theme="dark">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title><?= htmlspecialchars($TOOL_TITLE) ?>｜マッハーツール</title>
    <meta name="description" content="<?= htmlspecialchars($TOOL_DESC) ?>" />

    <!-- Leaflet (ローカル同梱: CDN 非依存) -->
    <link rel="stylesheet" href="vendor/leaflet/leaflet.css" />
    <link rel="stylesheet" href="assets/flight-radar.css" />
  </head>
  <body>
    <!-- MACH:HEADER  ← 本番ではマッハーツール共通ヘッダーの include に差し替え可 -->
    <header class="mt-header">
      <a class="mt-brand" href="/" title="マッハーツール">
        <span class="mt-logo">⚡</span>
        <span class="mt-brandname">マッハーツール</span>
      </a>
      <div class="mt-header-actions">
        <span class="mt-cat">地図・検索</span>
        <button id="themeBtn" class="mt-iconbtn" title="テーマ切替" aria-label="テーマ切替">🌙</button>
      </div>
    </header>

    <main class="mt-main">
      <div class="mt-toolhead">
        <h1>✈ フライトレーダー</h1>
        <p class="mt-lead">
          いま上空を飛んでいる航空機を地図にリアルタイム表示。機体をクリックすると便名・高度・速度がわかります。<b>登録不要・無料</b>。
        </p>
      </div>

      <div class="fr-panel">
        <div class="fr-toolbar">
          <div class="fr-status" id="status">
            <span class="dot" id="statusDot"></span>
            <span id="statusText">接続中…</span>
          </div>
          <div class="fr-controls">
            <label class="fr-switch">
              <input type="checkbox" id="autoRefresh" checked />
              <span>自動更新</span>
            </label>
            <button id="refreshBtn" class="fr-btn" title="今すぐ更新">⟳ 更新</button>
          </div>
        </div>

        <div id="map"></div>

        <div class="fr-stats">
          <span><strong id="planeCount">0</strong> 機を表示中</span>
          <span class="sep">·</span>
          <span id="lastUpdate">—</span>
          <span class="sep">·</span>
          <span>データ: <a href="https://opensky-network.org" target="_blank" rel="noopener">OpenSky Network</a></span>
        </div>
      </div>

      <!-- 選択機体の詳細 -->
      <aside id="detail" class="fr-detail hidden">
        <button class="close" id="detailClose" aria-label="閉じる">×</button>
        <h2 id="dCallsign">—</h2>
        <div class="badge" id="dCountry">—</div>
        <dl class="detail-grid">
          <div><dt>高度</dt><dd id="dAltitude">—</dd></div>
          <div><dt>速度</dt><dd id="dSpeed">—</dd></div>
          <div><dt>進行方向</dt><dd id="dTrack">—</dd></div>
          <div><dt>上昇/降下</dt><dd id="dVert">—</dd></div>
          <div><dt>ICAO24</dt><dd id="dIcao">—</dd></div>
          <div><dt>スコーク</dt><dd id="dSquawk">—</dd></div>
          <div><dt>緯度</dt><dd id="dLat">—</dd></div>
          <div><dt>経度</dt><dd id="dLon">—</dd></div>
        </dl>
        <a id="dExtLink" class="ext-link" href="#" target="_blank" rel="noopener">OpenSky で詳細を見る ↗</a>
      </aside>

      <section class="mt-about">
        <h2>このツールについて</h2>
        <ul>
          <li><b>使い方</b>：地図をドラッグ／ズームすると、その範囲の航空機を自動取得します。機体アイコンをクリックすると詳細が表示されます。</li>
          <li><b>データ元</b>：<a href="https://opensky-network.org" target="_blank" rel="noopener">OpenSky Network</a>（世界中のボランティア受信機によるオープンな航空機データ）。</li>
          <li><b>プライバシー</b>：マッハーツール側で位置データを保存・収集することはありません。航空機データの取得のためだけにサーバーを中継しています。</li>
          <li><b>ご注意</b>：受信機のカバレッジは地域差があります。無料データのため一時的に表示されないことがあります。安全・運航用途には使用しないでください。</li>
        </ul>
      </section>
    </main>

    <!-- MACH:FOOTER  ← 本番ではマッハーツール共通フッターの include に差し替え可 -->
    <footer class="mt-footer">
      <p>面倒な作業をマッハで解決する — <b>マッハーツール</b></p>
      <p class="mt-fineprint">
        当ツールは無料でご利用いただけます（商用利用可）。航空機データは OpenSky Network に帰属します。
      </p>
    </footer>

    <script src="vendor/leaflet/leaflet.js"></script>
    <script>
      // マッハーツールに組み込む際、API のパスが変わる場合はここで上書き
      window.FR_API_ENDPOINT = "api/states.php";
    </script>
    <script src="assets/flight-radar.js"></script>
  </body>
</html>
