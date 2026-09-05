# echonet_lite_gem

ECHONET Lite対応機器と通信するためのRuby Gemです。ECHONET Lite電文の生成・解析、機器ノードの検索、プロパティの取得・設定を提供します。

## 特徴

- ECHONET Lite電文の生成と解析
- ECHONET Liteノードの検索とEOJ情報の取得
- 機器のEPC一覧、プロパティ名、状態値の参照
- UDPによるマルチキャスト、ブロードキャスト、個別ノードへの通信
- HEMS、エアコン、電気温水器向けのコントローラ

## 必要条件

- Ruby 3.2.0以上
- ECHONET Lite機器と同じネットワークに接続されていること（通信時）

## インストール

アプリケーションのGemfileに追加します。

```ruby
gem "echonet_lite_gem"
```

その後、Bundlerでインストールします。

```sh
bundle install
```

ローカルのソースから試す場合は、リポジトリのルートで次を実行します。

```sh
bin/setup
```

## 使い方

### ECHONET Lite電文を生成する

EPC、PDC、EDTには16進数文字列を指定します。`make_telegram`の戻り値はUDP送信用のバイナリ文字列です。

```ruby
require "echonet_lite_gem"

telegram = EchonetLiteGem::ETelegram.new(
    seoj: "05FF01", # HEMSコントローラ
    deoj: "026B01", # 電気温水器のインスタンス1
    esv: "62",      # Get
    opc: 1,
    epc: ["80"],    # 動作状態
    pdc: [0]
)

payload = telegram.make_telegram
```

### 電文を解析する

受信したUDPペイロードは`EchonetNode#read`で`ETelegram`に変換できます。

```ruby
node = EchonetLiteGem::EchonetNode.new
telegram = node.read(payload)

puts telegram.tid
puts telegram.seoj
puts telegram.deoj
puts telegram.edt_hash("I")

node.shutdown
```

`EchonetNode`は内部でUDPソケットと受信スレッドを使用します。処理が終わったら`shutdown`を呼び出してください。

### ネットワーク上の機器を検索する

`HEMSController#search`は、ネットワーク上で見つかった機器を`EInstance`の配列として返します。通常はマルチキャストを使用します。

```ruby
hems = EchonetLiteGem::HEMSController.new

instances = hems.search
instances.each do |instance|
    puts "#{instance.ip} #{instance.eoj} #{instance.data["オブジェクト"]}"
end

hems.shutdown
```

ブロードキャストで検索する場合は`hems.search("broadcast")`を使用します。特定のEOJクラスだけを対象にする場合は、`target_node_eoj`を設定して`target_nodes`を呼び出します。

```ruby
hems.target_node_eoj = "026B"
water_heaters = hems.target_nodes
```

### プロパティを取得・設定する

`EInstance`を指定して、EPCの値を取得または設定します。EDTは偶数桁の16進数文字列で指定します。

```ruby
instance = water_heaters.first

# 動作状態を取得
state = hems.data_get(["80"], instance)

# 動作状態をONに設定
hems.data_set(["80"], ["30"], instance)

# よく使う操作
hems.power_on(instance)
hems.power_off(instance)
hems.change_power_state(instance)
```

取得したEPCの意味を調べるには、リリースバージョンを設定して`epc_list`または`get_epc_name`を使用します。

```ruby
instance.release = "I"
puts instance.get_epc_name("80")
instance.epc_list.each { |property| puts property }
```

## 通信について

- ECHONET LiteのUDPポート`3610`を使用します。
- マルチキャストアドレスは`224.0.23.0`です。
- `EchonetNode#send`の送信先には、`EInstance`、`"multicast"`、`"broadcast"`のいずれかを指定できます。
- 通信処理では、ファイアウォールやネットワーク機器がUDP 3610番とマルチキャストを許可している必要があります。

### セキュリティに関する注意

ECHONET Liteの通信には、認証や暗号化の仕組みがありません。このGemは同一LAN内の信頼できるネットワークで使用し、UDP 3610番をインターネットへ公開しないでください。

`data_set`、`power_on`、`power_off`などのメソッドは、接続された機器の状態を実際に変更します。利用前に送信先の機器と操作内容を確認し、必要に応じてファイアウォールで通信元を制限してください。

## 開発

依存関係をインストールします。

```sh
bin/setup
```

テストを実行します。

```sh
bundle exec rake spec
```

対話的に動作を確認する場合は、次を実行します。

```sh
bin/console
```

ローカル環境へGemをインストールする場合は`bundle exec rake install`を使用します。

## Contributing

バグ報告やプルリクエストを歓迎します。変更を送る前に、`bundle exec rake spec`でテストを実行してください。参加者は[Code of Conduct](CODE_OF_CONDUCT.md)に従ってください。

## License

このGemのオリジナルのコードおよびドキュメントは[MIT License](LICENSE.txt)のもとで公開されています。

ただし、`lib/echonet_lite_gem/data/mraData/` に同梱しているMachine Readable Appendix（MRA）データは、このMIT Licenseの対象ではありません。MRAデータの出典、著作権表示、データライセンスについては[DATA_LICENSE.txt](DATA_LICENSE.txt)を参照してください。
