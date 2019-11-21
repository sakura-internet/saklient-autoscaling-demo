# Saklient AutoScaling Demo

Ruby版のSaklientを用いたAutoScalingのデモプログラムです。

## 前提

本デモプログラムの実行前に、必要なリソース郡を下記の記事を参考に作成して頂く必要があります。  
[【TIPS】さくらのクラウドでAuto Scaling  |  さくらのクラウドニュース](http://cloud-news.sakura.ad.jp/2016/03/18/auto-scaling/)  
※ 作成するサーバには `autoscaling-demo` タグを付与してください。  

## 注意

デモプログラムの実行により、課金対象のリソースが作成されます。その点ご留意の上、実行していただくようにお願いいたします。

## 動作確認済み環境

- Ruby 2.1-2.6
- Saklient 0.0.10

## 使い方

### プロジェクトのclone

```shell
git clone git@github.com:sakura-internet/saklient-autoscaling-demo.git
cd saklient-autoscaling-demo
```

### gemの取得

```shell
bundle install --path vendor/bundle
```

### configファイルの作成

```shell
cp config/config.yml.example config/config.yml
```

### configファイルの編集

以下の値を設定

- APIキー
- ゾーン
- 1.で作成したリソースのID

### デモプログラムの起動

```shell
bundle ex ./bin/demo
```

## TIPS

実際にオートスケールする様子を確認するには、サーバに負荷をかける必要があります。  
本プログラムではCPU-TIMEを監視しているため、CPUに負荷をかける例を紹介します。

サーバにログインした上で以下のコマンドを実行

```shell
openssl speed
```

## 仕様

- デモプログラムが起動されると、対象のサーバ( `autoscaling-demo` タグが付与されたサーバ)の負荷状態が監視されます
  - 対象サーバのCPU-TIMEの平均が `cpu_time_scale_out_threshold` の値より大きくなるとスケールアウトされます
  - 対象サーバのCPU-TIMEの平均が `cpu_time_scale_in_threshold` の値より小さくなるとスケールインされます
- 監視間隔は `5分` です（APIで取得されるCPU-TIMEの値が5分ごとに更新されるため）
- サーバは最大 `max_servers_count` の値までスケールアウトされます
- サーバは最小 `min_servers_count` の値までスケールインされます
