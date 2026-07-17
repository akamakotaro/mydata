# フライトレーダー（マッハーツール版）

マッハーツールに組み込むための **PHP + ブラウザ完結** 版フライトレーダーです。
OpenSky Network のオープンデータで、いま上空を飛んでいる航空機を地図にリアルタイム表示します。

> リポジトリ直下の Node.js/Express 版と機能は同じで、こちらは
> **マッハーツールの PHP スタックにそのまま載る**ように作り替えたものです。

## なぜ PHP プロキシが必要か

OpenSky API は CORS で自ドメイン（`opensky-network.org`）以外からのブラウザ直アクセスを
許可していません。そのため航空機データの取得だけはサーバー側で中継する必要があります。
`api/states.php` がその役割を担い、**位置データの保存・収集はしません**（6 秒だけ一時
ファイルにキャッシュし、OpenSky の匿名レート制限を緩和します）。DB は不使用です。

## ファイル構成

```
mach-tools/
├── flight-radar.php        # ツールページ本体（マッハーツール風UI・ダーク/ライト対応）
├── api/
│   └── states.php          # OpenSky プロキシ（cURL・一時ファイルキャッシュ）
├── assets/
│   ├── flight-radar.css    # スタイル（data-theme で dark/light 切替）
│   └── flight-radar.js     # 地図描画・自動更新・テーマ切替
└── vendor/leaflet/         # Leaflet 1.9.4 一式（CDN 非依存）
```

## 動作要件

- PHP 7.4+（`curl` 拡張が有効なこと）
- 送信側サーバーから `https://opensky-network.org` へアウトバウンド通信ができること

## ローカル確認

```bash
cd mach-tools
php -S 127.0.0.1:8080
# → http://127.0.0.1:8080/flight-radar.php
```

## マッハーツールへの組み込み

1. `mach-tools/` の中身を、ツール用ディレクトリ（例: `/tools/flight-radar/`）に配置します。
2. `flight-radar.php` 内の `<!-- MACH:HEADER -->` / `<!-- MACH:FOOTER -->` を、
   マッハーツール共通のヘッダー/フッター `include` に差し替えます。
3. API のパスがサイト構成で変わる場合は、`flight-radar.php` 末尾の
   ```html
   <script>window.FR_API_ENDPOINT = "api/states.php";</script>
   ```
   を実際のパスに合わせて変更します（相対パスでも絶対パスでも可）。
4. トップページの「地図・検索」カテゴリにツールカード／リンクを追加します。

### テーマ連携

- テーマは `<html data-theme="dark|light">` で制御し、ページ内のボタンで切替・
  `localStorage`（キー `mt-flightradar-theme`）に保存します。
- マッハーツール共通のテーマ管理がある場合は、`data-theme` を共通側で付与し、
  `assets/flight-radar.js` のテーマボタン処理を共通の仕組みに合わせてください
  （地図タイルは `data-theme` を見て自動でダーク/ライトに追従します）。

## OpenSky 認証（任意・推奨）

匿名利用はレート上限が低めです。無料の OpenSky アカウントで OAuth2 クライアントを作成し、
サーバーの環境変数に設定すると上限が上がります。

```
OPENSKY_CLIENT_ID=xxxxxxxx
OPENSKY_CLIENT_SECRET=xxxxxxxx
```

（`api/states.php` が自動で検出してトークンを取得・キャッシュします。未設定でも動作します。）

## 注意事項

- OpenSky のデータはボランティア受信機に依存するため、**地域によってカバレッジに差**があります。
- 無料枠のため、混雑時は一時的にデータ取得に失敗することがあります（その場合は直近の
  キャッシュを返します）。
- 本ツールは情報提供・娯楽目的です。航空管制・運航など安全用途には使用しないでください。
