RSpec.describe EchonetLiteGem::HEMSController do
  let(:udp_socket) { instance_double(UDPSocket) }

  before do
    Singleton.__init__(EchonetLiteGem::UDPManager)
    @recv_queue = Queue.new

    allow(UDPSocket).to receive(:new).and_return(udp_socket)

    allow(udp_socket).to receive(:close) do
      @recv_queue << IOError.new
      nil
    end

    allow(udp_socket).to receive(:bind)
    allow(udp_socket).to receive(:setsockopt)
    allow(udp_socket).to receive(:send)
    allow(udp_socket).to receive(:connect)

    allow(udp_socket).to receive(:recvfrom) do
      value = @recv_queue.pop
      raise value if value.is_a?(Exception)

      value
    end

    allow_any_instance_of(EchonetLiteGem::UDPManager).to receive(:selfip).and_return('192.168.0.11')
    @hc = EchonetLiteGem::HEMSController.new
    @ecocute = EchonetLiteGem::EInstance.new(ip: '192.168.0.250', clg: '02', cls: '6B', itc: '01')
    @ecocute.release = "I"
    @msg1 = "\x10\x81\x00\x01\x0E\xF0\x01\x05\xFF\x01\x72\x01\xD6\x04\x01\x02\x6B\x01" # エコキュート
    @msg1.force_encoding("ASCII-8BIT")
    @msg2 = "\x10\x81\x00\x01\x0E\xF0\x01\x05\xFF\x01\x72\x01\xD6\x04\x01\x01\x30\x01" # エアコン
    @msg2.force_encoding("ASCII-8BIT")
    @msg3 = "\x10\x81\x00\x01\x0E\xF0\x01\x05\xFF\x01\x72\x01\xD6\x04\x01\x01\x30\x01" # エアコン
    @msg3.force_encoding("ASCII-8BIT")
    @msg_exempt = "\x10\x81\x00\x01\x0E\xF0\x01\x05\xFF\x01\x72\x01\x80\x01\x30" # EPC:0x８０(動作状態)
    @msg_exempt.force_encoding("ASCII-8BIT")
    @msg_release = "\x10\x81\x00\x02\x02k\x01\x05\xFF\x01r\x01\x82\x04\x00\x00I\x00" # release番号の返答電文（release番号は”I”）
    @msg_release.force_encoding("ASCII-8BIT")
    @msg_release2 = "\x10\x81\x00\x03\x02k\x01\x05\xFF\x01r\x01\x82\x04\x00\x00I\x00" # release番号の返答電文（release番号は”I”）
    @msg_release2.force_encoding("ASCII-8BIT")
    @msg_release3 = "\x10\x81\x00\x04\x02k\x01\x05\xFF\x01r\x01\x82\x04\x00\x00I\x00" # release番号の返答電文（release番号は”I”）
    @msg_release3.force_encoding("ASCII-8BIT")
    @msg_ok = "\x10\x81\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" # recv_thread動作完了通知用電文
    @msg_ok.force_encoding("ASCII-8BIT")
    @resp_q = @hc.instance_variable_get(:@udp).instance_variable_get(:@response_queue)
    allow(@hc).to receive(:check_tid).and_return(true)
  end

  after do
    @hc.shutdown if @hc && (worker = @hc.instance_variable_get(:@recv_worker)) && worker.alive?
  end

  describe '#search' do
    it 'ネットワークに存在するECHONET Liteのノードを探索して、EInstanceクラスの配列として返す' do
      @recv_queue << [@msg1, ["RSpec TEST", 3610, "", "192.168.0.250"]]
      @recv_queue << [@msg_release, ["RSpec TEST", 3610, "", "192.168.0.250"]]
      @recv_queue << [@msg_ok, []] # recv_thread実行確認用のパケット
      @resp_q[0].pop # recv_thread実行完了の確認
      nodes = @hc.search
      expect(nodes).to all(be_a(EchonetLiteGem::EInstance))
      expect(nodes).not_to be_empty
    end
    it '引数なしで呼ぶと、multicastでECHONET Liteノードを探索する' do
      allow(@hc).to receive(:send).and_call_original
      @recv_queue << [@msg1, ["RSpec TEST", 3610, "", "192.168.0.250"]]
      @recv_queue << [@msg_release, ["RSpec TEST", 3610, "", "192.168.0.250"]]
      @recv_queue << [@msg_ok, []] # recv_thread実行確認用のパケット
      @resp_q[0].pop # recv_thread実行完了の確認
      @hc.search
      expect(@hc).to have_received(:send).with(anything, "multicast")
    end

    it 'EPCが0xD6（自ノードインスタンスリストS）の電文のみノード情報と判断。それ以外は廃棄' do
      @recv_queue << [@msg1, ["AF_INET", 3610, "", "192.168.0.250"]]
      @recv_queue << [@msg2, ["AF_INET", 3610, "", "192.168.0.260"]]
      @recv_queue << [@msg_exempt, ["RSpec TEST", 3610, "", "192.168.0.150"]]
      @recv_queue << [@msg_release, ["RSpec TEST", 3610, "", "192.168.0.250"]]
      @recv_queue << [@msg_release2, ["RSpec TEST", 3610, "", "192.168.0.250"]]
      @recv_queue << [@msg_ok, []] # recv_thread実行確認用のパケット
      @resp_q[0].pop # recv_thread実行完了の確認
      nodes = @hc.search
      expect(nodes.length).to eq(2)
    end
    it 'response_queueからのデータ待ちに0.5秒経過するとタイムアウトして終了する' do
      expect(Timeout).to receive(:timeout).with(0.5).and_raise(Timeout::Error)

      expect(@hc.search).to eq []
    end

    it 'release_versionが取得できる' do
      @recv_queue << [@msg1, ["RSpec TEST", 3610, "", "192.168.0.250"]]
      @recv_queue << [@msg_release, ["RSpec TEST", 3610, "", "192.168.0.250"]]
      @recv_queue << [@msg_ok, []] # recv_thread実行確認用のパケット
      @resp_q[0].pop # recv_thread実行完了の確認
      nodes = @hc.search

      expect { nodes[0].epc_list }.not_to raise_error
    end
  end

  describe '#target_nodes' do
    describe '@target_node_eojに設定したEOJコードに一致するECHONETノードを探索して、EInstanceクラスの配列として返す' do
      it '@target_node_eojが0130の場合は、エアコンのノードを探索して、EInstanceクラスの配列として返す' do
        @recv_queue << [@msg1, ["AF_INET", 3610, "", "192.168.0.250"]]
        @recv_queue << [@msg2, ["AF_INET", 3610, "", "192.168.0.260"]]
        @recv_queue << [@msg3, ["RSpec TEST", 3610, "", "192.168.0.230"]]
        @recv_queue << [@msg_release, ["RSpec TEST", 3610, "", "192.168.0.250"]]
        @recv_queue << [@msg_release2, ["RSpec TEST", 3610, "", "192.168.0.250"]]
        @recv_queue << [@msg_release3, ["RSpec TEST", 3610, "", "192.168.0.250"]]
        @recv_queue << [@msg_ok, []] # recv_thread実行確認用のパケット
        @resp_q[0].pop # recv_thread実行完了の確認
        @hc.target_node_eoj = "0130"
        nodes = @hc.target_nodes
        expect(nodes).to all(have_attributes(clg: '01', cls: '30'))
        expect(nodes.size).to eq 2
      end

      it '@target_node_eojが026bの場合は、エコキュートのノードを探索して、EInstanceクラスの配列として返す' do
        @recv_queue << [@msg1, ["AF_INET", 3610, "", "192.168.0.250"]]
        @recv_queue << [@msg2, ["AF_INET", 3610, "", "192.168.0.260"]]
        @recv_queue << [@msg3, ["RSpec TEST", 3610, "", "192.168.0.230"]]
        @recv_queue << [@msg_release, ["RSpec TEST", 3610, "", "192.168.0.250"]]
        @recv_queue << [@msg_release2, ["RSpec TEST", 3610, "", "192.168.0.250"]]
        @recv_queue << [@msg_release3, ["RSpec TEST", 3610, "", "192.168.0.250"]]
        @recv_queue << [@msg_ok, []] # recv_thread実行確認用のパケット
        @resp_q[0].pop # recv_thread実行完了の確認
        @hc.target_node_eoj = "026B"
        nodes = @hc.target_nodes
        expect(nodes).to all(have_attributes(clg: '02', cls: '6B'))
        expect(nodes.size).to eq 1
      end
    end
  end

  describe '#data_get' do
    it '第二引数に指定したEInstanceから、第一引数で指定したECHONETプロパティのデータを取得する。' do
      msg = "\x10\x81\x00\x01\x02k\x01\x05\xFF\x01r\x01\xE1\x02\x00\xC8"
      msg.force_encoding("ASCII-8BIT")
      @recv_queue << [msg, ["RSpec TEST", 3610, "", "192.168.0.250"]]
      @recv_queue << [@msg_ok, []] # recv_thread実行確認用のパケット
      @resp_q[0].pop # recv_thread実行完了の確認

      hash = { 'E1' => 200 }
      expect(@hc.data_get(['E1'], @ecocute)).to eq hash
    end
    it '第二引数に指定したEInstanceから、第一引数で指定したECHONETプロパティのデータを標準出力に出力。' do
      msg = "\x10\x81\x00\x01\x02k\x01\x05\xFF\x01r\x01\xE1\x02\x00\xC8"
      msg.force_encoding("ASCII-8BIT")
      @recv_queue << [msg, ["RSpec TEST", 3610, "", "192.168.0.250"]]
      @recv_queue << [@msg_ok, []] # recv_thread実行確認用のパケット
      @resp_q[0].pop # recv_thread実行完了の確認

      data = <<~DATA
        残湯量計測値:200
      DATA
      expect { @res = @hc.data_get(['E1'], @ecocute) }.to output(data).to_stdout
    end
    it '第一引数が配列でないとエラーが発生する' do
      expect { @hc.data_get('E1', @ecocute) }.to raise_error 'epcはArrayを指定して下さい'
    end

    it '第二引数がEInstanceでない場合はエラーが発生する' do
      expect { @hc.data_get(['E1'], 'ecocute') }.to raise_error 'target_instanceが正しく指定されていません'
    end

    it '応答がタイムアウトすると3回リトライして空のハッシュを返す' do
      allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)
      expect(@hc).to receive(:send).exactly(3).times.with(instance_of(EchonetLiteGem::ETelegram), @ecocute)

      expect(@hc.data_get(['E1'], @ecocute)).to eq({})
    end

    it 'Interruptが発生するとリトライせず空のハッシュを返す' do
      allow(Timeout).to receive(:timeout).and_raise(Interrupt)
      expect(@hc).to receive(:send).once.with(instance_of(EchonetLiteGem::ETelegram), @ecocute)

      expect(@hc.data_get(['E1'], @ecocute)).to eq({})
    end

    it 'node_profileを指定するとノードプロファイル宛てに問い合わせる' do
      allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)
      expect(@hc).to receive(:send).exactly(3).times do |message, target_instance|
        expect(message.deoj).to eq '0EF001'
        expect(target_instance).to eq @ecocute
      end

      expect(@hc.data_get(['E1'], @ecocute, node_profile: true)).to eq({})
    end

    it 'releaseバージョンに合うデータを取得できる。' do
      msg = "\x10\x81\x00\x01\x02k\x01\x05\xFF\x01r\x01\x93\x01a"
      msg.force_encoding("ASCII-8BIT")
      @recv_queue << [msg, ["RSpec TEST", 3610, "", "192.168.0.250"]]
      @recv_queue << [@msg_ok, []] # recv_thread実行確認用のパケット
      @resp_q[0].pop # recv_thread実行完了の確認

      hash = { '93' => "通信回線正常(公衆回線経由の操作不可)" }
      data = <<~DATA
        遠隔操作設定:通信回線正常(公衆回線経由の操作不可)
      DATA
      expect { @res = @hc.data_get(['93'], @ecocute) }.to output(data).to_stdout
      expect(@res).to eq hash
    end

    it 'searchメソッドで探索した相手からreleaseバージョン通りのデータが取得できる' do
      search_res_msg = "\x10\x81\x00\x01\x0E\xF0\x01\x05\xFF\x01r\x01\xD6\x04\x01\x02k\x01"
      search_res_msg.force_encoding("ASCII-8BIT")
      @recv_queue << [search_res_msg, ["RSpec TEST", 3610, "", "192.168.0.250"]]
      @recv_queue << [@msg_release, ["RSpec TEST", 3610, "", "192.168.0.250"]]
      @recv_queue << [@msg_ok, []] # recv_thread実行確認用のパケット
      @resp_q[0].pop # recv_thread実行完了の確認

      node_instance = @hc.search[0]

      msg1 = "\x10\x81\x00\x03\x02k\x01\x05\xFF\x01r\x01\x93\x01a" # 遠隔操作設定の返答電文
      msg1.force_encoding("ASCII-8BIT")
      msg2 = "\x10\x81\x00\x04\x02k\x01\x05\xFF\x01r\x01\x82\x04\x00\x00I\x00" # release番号の返答電文（release番号は”I”）
      msg2.force_encoding("ASCII-8BIT")
      @recv_queue << [msg1, ["RSpec TEST", 3610, "", "192.168.0.250"]]
      @recv_queue << [msg2, ["RSpec TEST", 3610, "", "192.168.0.250"]]
      @recv_queue << [@msg_ok, []] # recv_thread実行確認用のパケット
      @resp_q[0].pop # recv_thread実行完了の確認

      hash = { '93' => "通信回線正常(公衆回線経由の操作不可)" }
      data = <<~DATA
        遠隔操作設定:通信回線正常(公衆回線経由の操作不可)
      DATA
      expect { @res = @hc.data_get(['93'], node_instance) }.to output(data).to_stdout
      expect(@res).to eq hash
    end
  end

  describe '#data_set' do
    it '送信したETelegramインスタンスを戻り値で返す' do
      expect(@hc.data_set(['B0'], ['43'], @ecocute)).to be_instance_of(EchonetLiteGem::ETelegram)
    end

    it '送信したETelegramインスタンスのメッセージが正しい電文になっている' do
      msg = @hc.data_set(['B0'], ['43'], @ecocute)
      expect(msg.seoj).to eq '05FF01'
      expect(msg.deoj).to eq '026B01'
      expect(msg.esv).to eq '60'
      expect(msg.opc).to eq 1
      expect(msg.epc).to eq ["B0"]
      expect(msg.pdc).to eq [1]
      expect(msg.edt).to eq ["43"]
    end

    it '第一引数,第二引数が配列でないとエラーが発生する' do
      expect { @hc.data_set('E0', ['43'], @ecocute) }.to raise_error 'epcはArrayを指定して下さい'
      expect { @hc.data_set(['E0'], '43', @ecocute) }.to raise_error 'edtはArrayを指定して下さい'
    end

    it 'EPCとEDTの配列要素数が一致しないとエラーが発生する' do
      expect do
        @hc.data_set(%w[B0 B3], ['43'], @ecocute)
      end.to raise_error 'epcとedtの要素数を一致させて下さい'
    end

    it 'target_instanceがEInstanceでないとエラーが発生する' do
      expect do
        @hc.data_set(['B0'], ['43'], 'ecocute')
      end.to raise_error 'target_instanceにはEInstanceを指定して下さい'
    end

    it 'edtに不正な16進数文字列を指定するとエラーが発生する' do
      expect do
        @hc.data_set(['B0'], ['GG'], @ecocute)
      end.to raise_error 'edtは偶数桁の16進数文字列を指定して下さい'
    end

    it 'edtに奇数桁の16進数文字列を指定するとエラーが発生する' do
      expect do
        @hc.data_set(['B0'], ['1'], @ecocute)
      end.to raise_error 'edtは偶数桁の16進数文字列を指定して下さい'
    end

    it 'pdcは、第二引数の値を元に自動で計算される' do
      expect(@hc.data_set(['91'], ['0A1E'], @ecocute).pdc).to eq [2]
    end

    it '複数プロパティのpdcをそれぞれ正しく計算する' do
      message = @hc.data_set(%w[B0 B3], %w[43 1C], @ecocute)

      expect(message.epc).to eq %w[B0 B3]
      expect(message.edt).to eq %w[43 1C]
      expect(message.pdc).to eq [1, 1]
    end

    it 'data_setした対象のキャッシュはnilになる（cached_data_getメソッドで最新データに更新できるように）' do
      cache_key = "#{@ecocute.ip}:#{@ecocute.eoj}:B0"
      @hc.instance_variable_set(:@data_cache, { cache_key => { response: { '80' => '31' }, expires_at: Time.now + 60 } })

      @hc.data_set(['B0'], ['43'], @ecocute)

      expect(@hc.instance_variable_get(:@data_cache)[cache_key]).to be_nil
    end
  end

  describe '#cached_data_get' do
    it 'TTL内の同じ問い合わせではdata_getを一度だけ呼び出す' do
      response = { 'E1' => 200 }
      allow(@hc).to receive(:data_get).and_return(response)

      expect(@hc.cached_data_get(['E1'], @ecocute, ttl: 60)).to eq response
      expect(@hc.cached_data_get(['E1'], @ecocute, ttl: 60)).to eq response

      expect(@hc).to have_received(:data_get).once.with(['E1'], @ecocute)
    end

    it 'TTL内ではキャッシュを使い、TTL経過後はdata_getを再度呼び出す' do
      first_response = { 'E1' => 200 }
      second_response = { 'E1' => 250 }
      allow(@hc).to receive(:data_get).and_return(first_response, second_response)
      allow(Time).to receive(:now).and_return(Time.at(100), Time.at(100.5), Time.at(101.1))

      expect(@hc.cached_data_get(['E1'], @ecocute, ttl: 1)).to eq first_response
      expect(@hc.cached_data_get(['E1'], @ecocute, ttl: 1)).to eq first_response
      expect(@hc.cached_data_get(['E1'], @ecocute, ttl: 1)).to eq second_response

      expect(@hc).to have_received(:data_get).twice.with(['E1'], @ecocute)
    end

    it '異なるEPCの問い合わせは別々にキャッシュする' do
      first_response = { 'E1' => 200 }
      second_response = { 'E2' => 42 }
      allow(@hc).to receive(:data_get).and_return(first_response, second_response)

      expect(@hc.cached_data_get(['E1'], @ecocute, ttl: 60)).to eq first_response
      expect(@hc.cached_data_get(['E2'], @ecocute, ttl: 60)).to eq second_response

      expect(@hc).to have_received(:data_get).twice
    end

    it '異なる対象インスタンスの問い合わせは別々にキャッシュする' do
      another_ecocute = EchonetLiteGem::EInstance.new(
        ip: '192.168.0.251',
        clg: '02',
        cls: '6B',
        itc: '01'
      )
      first_response = { 'E1' => 200 }
      second_response = { 'E1' => 150 }
      allow(@hc).to receive(:data_get).and_return(first_response, second_response)

      expect(@hc.cached_data_get(['E1'], @ecocute, ttl: 60)).to eq first_response
      expect(@hc.cached_data_get(['E1'], another_ecocute, ttl: 60)).to eq second_response

      expect(@hc).to have_received(:data_get).twice
    end
  end

  describe '#check_power_state' do
    it 'Nodeの電源のON/OFFの状態を確認できる' do
      msg = "\x10\x81\x00\x01\x02k\x01\x05\xFF\x01r\x01\x80\x010"
      msg.force_encoding("ASCII-8BIT")
      @recv_queue << [msg, ["RSpec TEST", 3610, "", "192.168.0.250"]]
      @recv_queue << [@msg_ok, []] # recv_thread実行確認用のパケット
      @resp_q[0].pop # recv_thread実行完了の確認

      hash = 'ON'
      data = <<~DATA
        動作状態:ON
      DATA
      expect { @res = @hc.check_power_state(@ecocute) }.to output(data).to_stdout
      expect(@res).to eq hash
    end
  end

  describe '#check_location' do
    it 'Nodeの設置場所を確認できる' do
      allow(@hc).to receive(:data_get).with(['81'], @ecocute).and_return('81' => '18')

      expect(@hc.check_location(@ecocute)).to eq 'キッチン'
    end
  end

  describe '#change_power_state' do
    it '電源がONの場合はpower_offを呼び出す' do
      allow(@hc).to receive(:check_power_state).with(@ecocute).and_return('ON')
      expect(@hc).to receive(:power_off).with(@ecocute).and_return(:powered_off)

      expect(@hc.change_power_state(@ecocute)).to eq :powered_off
    end

    it '電源がOFFの場合はpower_onを呼び出す' do
      allow(@hc).to receive(:check_power_state).with(@ecocute).and_return('OFF')
      expect(@hc).to receive(:power_on).with(@ecocute).and_return(:powered_on)

      expect(@hc.change_power_state(@ecocute)).to eq :powered_on
    end
  end

  describe '#power_on' do
    it '送信したETelegramインスタンスを戻り値で返す' do
      expect(@hc.power_on(@ecocute)).to be_instance_of(EchonetLiteGem::ETelegram)
    end

    it '送信したETelegramインスタンスのメッセージが正しい電文になっている' do
      msg = @hc.power_on(@ecocute)
      expect(msg.seoj).to eq '05FF01'
      expect(msg.deoj).to eq '026B01'
      expect(msg.esv).to eq '60'
      expect(msg.opc).to eq 1
      expect(msg.epc).to eq ["80"]
      expect(msg.pdc).to eq [1]
      expect(msg.edt).to eq ["30"]
    end
  end

  describe '#power_off' do
    it '送信したETelegramインスタンスを戻り値で返す' do
      expect(@hc.power_off(@ecocute)).to be_instance_of(EchonetLiteGem::ETelegram)
    end

    it '送信したETelegramインスタンスのメッセージが正しい電文になっている' do
      msg = @hc.power_off(@ecocute)
      expect(msg.seoj).to eq '05FF01'
      expect(msg.deoj).to eq '026B01'
      expect(msg.esv).to eq '60'
      expect(msg.opc).to eq 1
      expect(msg.epc).to eq ["80"]
      expect(msg.pdc).to eq [1]
      expect(msg.edt).to eq ["31"]
    end
  end

  describe '#check_release_version' do
    it 'インスタンスのrelease番号を確認できる' do
      msg = "\x10\x81\x00\x01\x02k\x01\x05\xFF\x01r\x01\x82\x04\x00\x00I\x00"
      msg.force_encoding("ASCII-8BIT")
      @recv_queue << [msg, ["RSpec TEST", 3610, "", "192.168.0.250"]]
      @recv_queue << [@msg_ok, []] # recv_thread実行確認用のパケット
      @resp_q[0].pop # recv_thread実行完了の確認

      hash = 'I'
      expect { @res = @hc.check_release_version(@ecocute) }.not_to output.to_stdout
      expect(@res).to eq hash
    end

    it 'インスタンスのrelease番号を調べるreleaseプロバティがきちんと設定される' do
      msg = "\x10\x81\x00\x01\x02k\x01\x05\xFF\x01r\x01\x82\x04\x00\x00I\x00"
      msg.force_encoding("ASCII-8BIT")
      @recv_queue << [msg, ["RSpec TEST", 3610, "", "192.168.0.250"]]
      @recv_queue << [@msg_ok, []] # recv_thread実行確認用のパケット
      @resp_q[0].pop # recv_thread実行完了の確認

      hash = 'I'
      @ecocute.release = nil
      @hc.check_release_version @ecocute
      expect(@ecocute.release).to eq hash
    end
  end

  describe '#check_manufacturer' do
    it 'nodeのメーカーを確認できる' do
      msg = "\x10\x81\x00\x01\x02k\x01\x05\xFF\x01r\x01\x8A\x03\x00\x00\v"
      msg.force_encoding("ASCII-8BIT")
      @recv_queue << [msg, ["RSpec TEST", 3610, "", "192.168.0.250"]]

      res = 'パナソニック ホールディングス'
      data = <<~DATA
        メーカコード:00000B
      DATA
      expect { @res = @hc.check_manufacturer(@ecocute) }.to output(data).to_stdout
      expect(@res).to eq res
    end

    it '未知のメーカーコードの場合はnilを返す' do
      allow(@hc).to receive(:data_get).with(['8A'], @ecocute).and_return('8A' => 'FFFFFF')

      expect(@hc.check_manufacturer(@ecocute)).to be_nil
    end
  end

  describe '#check_product_code' do
    it 'nodeの商品コードを確認できる' do
      msg = "\x10\x81\x00\x01\x02k\x01\x05\xFF\x01r\x01\x8C\fMSZ-GE2524  "
      msg.force_encoding("ASCII-8BIT")
      @recv_queue << [msg, ["RSpec TEST", 3610, "", "192.168.0.250"]]
      @recv_queue << [@msg_ok, []] # recv_thread実行確認用のパケット
      @resp_q[0].pop # recv_thread実行完了の確認

      res = 'MSZ-GE2524'
      data = <<~DATA
        商品コード:4D535A2D4745323532342020
      DATA
      expect { @res = @hc.check_product_code(@ecocute) }.to output(data).to_stdout
      expect(@res).to eq res
    end

    it 'node_profileを指定するとノードプロファイルの商品コードを確認できる' do
      allow(@hc).to receive(:data_get).with(['8C'], @ecocute, node_profile: true).and_return('8C' => '4E4F')

      expect(@hc.check_product_code(@ecocute, node_profile: true)).to eq 'NO'
      expect(@hc).to have_received(:data_get).with(['8C'], @ecocute, node_profile: true)
    end
  end
end
