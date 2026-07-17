# ✈ Flight Radar Web App

OpenSky Network のオープンデータを使って、**リアルタイムで航空機を地図上に表示**するフライトレーダー風の Web アプリです。

![tech](https://img.shields.io/badge/Node.js-%E2%89%A518-green) ![tech](https://img.shields.io/badge/Leaflet-1.9-blue) ![data](https://img.shields.io/badge/data-OpenSky_Network-orange)

## 特徴

- 🛰 **リアルタイム表示** — 実際に飛行中の航空機を数秒ごとに更新
- 🧭 **進行方向で機体を回転** — 各機の向き (heading) をアイコンに反映
- 🖱 **クリックで詳細** — コールサイン・高度・速度・上昇/降下率・スコークなどを表示
- 🗺 **地図に追従** — 表示中の地図範囲だけを取得するので軽量
- 🔁 **自動更新のON/OFF** と手動更新ボタン
- 🌙 ダークテーマの見やすい UI（PC / スマホ対応）
- 🔑 **APIキー不要**（地図タイル・航空機データともに無料ソース）

## しくみ

```
ブラウザ (Leaflet)  ──►  /api/states  ──►  OpenSky Network API
     ▲                    (Express)          (states/all)
     └──── 地図描画 ◄──── キャッシュ ◄────────┘
```

- フロントエンド: **Leaflet + OpenStreetMap(CARTO dark)** タイル
- バックエンド: **Node.js + Express**。OpenSky API をプロキシして
  - ブラウザの CORS 問題を回避
  - 6 秒間の簡易キャッシュでレート制限を緩和
  - （任意）OpenSky の OAuth2 認証に対応

データ元: [OpenSky Network](https://opensky-network.org/) の `states/all` エンドポイント。

## 使い方

```bash
# 1. 依存パッケージをインストール
npm install

# 2. サーバー起動
npm start

# 3. ブラウザで開く
#    http://localhost:3000
```

`npm run dev` で `--watch` 付き（ファイル変更で自動再起動）でも起動できます。

### 環境変数（任意）

| 変数 | 説明 |
| --- | --- |
| `PORT` | サーバーのポート番号（既定: `3000`） |
| `OPENSKY_CLIENT_ID` | OpenSky の OAuth2 クライアントID（設定すると高いレート上限が使える） |
| `OPENSKY_CLIENT_SECRET` | 同 シークレット |

OpenSky のアカウントは無料で作成でき、認証なしでも利用できます（レート上限は低め）。
認証情報は [OpenSky のアカウント設定](https://opensky-network.org/my-opensky/account) から取得できます。

## 注意事項

- OpenSky の無料データはボランティアの受信機に依存するため、**カバレッジは地域により差**があります（欧州・北米・日本の主要空港周辺は良好）。
- 匿名利用にはレート制限があります。頻繁に更新すると一時的にデータが取得できないことがあります（その場合はキャッシュを返します）。
- 本アプリは学習・デモ目的です。航空管制など安全用途には使用しないでください。

## ライセンス

MIT
