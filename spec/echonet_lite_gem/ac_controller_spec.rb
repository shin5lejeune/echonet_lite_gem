RSpec.describe EchonetLiteGem::ACController do
  let(:udp_socket) { instance_double(UDPSocket) }

  before do
    Singleton.__init__(EchonetLiteGem::UDPManager)
    Singleton.__init__(EchonetLiteGem::ACController)
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
    @acc = EchonetLiteGem::ACController.instance
    @resp_q = @acc.instance_variable_get(:@udp).instance_variable_get(:@response_queue)
    @ac = EchonetLiteGem::EInstance.new(ip: '192.168.0.250', clg: '01', cls: '30', itc: '01')
    @ac.release = "I"

    @msg_ok = "\x10\x81\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" # recv_thread動作完了通知用電文
    @msg_ok.force_encoding("ASCII-8BIT")
  end

  after do
    @acc.shutdown if @acc && (worker = @acc.instance_variable_get(:@recv_worker)) && worker.alive?
  end

  describe '#check_operation_mode' do
    before do
      # msg = "\x10\x81\x00d\x010\x01\x05\xFF\x01r\x01\xB0\x01B"
      msg = [
        0x10, 0x81, 0x00, 0x01, # EHD1, EHD2, TID
        0x01, 0x30, 0x01, # SEOJ
        0x05, 0xFF, 0x01, # DEOJ
        0x72, # ESV プロパティ値読み出し応答
        0x01, # OPC
        0xB0, # EPC 運転モード設定
        0x01, # PDC
        0x42 # EDT 冷房
      ].pack("C*")
      msg.force_encoding("ASCII-8BIT")
      @recv_queue << [msg, ["RSpec TEST", 3610, "", "192.168.0.250"]]
      @recv_queue << [@msg_ok, []]
    end

    it 'ネットワーク内のエアコンから動作状態を取得する' do
      @resp_q[0].pop # recv_thread実行完了の確認

      expect(@acc.check_operation_mode(@ac, ttl: 0)).to eq '冷房' # ttl:0にすることで、以後のテストでのキャッシュによる未取得を防止
    end
  end

  describe '#check_target_temperature' do
    before do
      msg = [
        0x10, 0x81, 0x00, 0x01, # EHD1, EHD2, TID
        0x01, 0x30, 0x01, # SEOJ
        0x05, 0xFF, 0x01, # DEOJ
        0x72, # ESV プロパティ値読み出し応答
        0x01, # OPC
        0xB3, # EPC 目標温度設定値
        0x01, # PDC
        0x1B # EDT 27
      ].pack("C*")
      msg.force_encoding("ASCII-8BIT")
      @recv_queue << [msg, ["RSpec TEST", 3610, "", "192.168.0.250"]]
      @recv_queue << [@msg_ok, []]
    end

    it 'ネットワーク内のエアコンから設定温度を取得する' do
      @resp_q[0].pop # recv_thread実行完了の確認

      expect(@acc.check_target_temperature(@ac, ttl: 0)).to eq 27 # ttl:0にすることで、以後のテストでのキャッシュによる未取得を防止
    end
  end

  describe '#check_room_temperature' do
    it 'エアコンの室温を取得する' do
      allow(@acc).to receive(:ac_status).with(@ac, ttl: 1).and_return('BB' => 23)

      expect(@acc.check_room_temperature(@ac)).to eq 23
    end
  end

  describe '#check_automatic_swing_air_flow' do
    it 'エアコンの自動スイング設定を取得する' do
      allow(@acc).to receive(:ac_status).with(@ac, ttl: 1).and_return('A3' => 'ON')

      expect(@acc.check_automatic_swing_air_flow(@ac)).to eq 'ON'
    end
  end

  describe '#check_automatic_control_air_flow_direction' do
    it 'エアコンの自動風向制御設定を取得する' do
      allow(@acc).to receive(:ac_status).with(@ac, ttl: 1).and_return('A1' => '自動')

      expect(@acc.check_automatic_control_air_flow_direction(@ac)).to eq '自動'
    end
  end

  describe '#check_air_flow_direction_vertical' do
    it 'エアコンの上下風向設定を取得する' do
      allow(@acc).to receive(:ac_status).with(@ac, ttl: 1).and_return('A4' => '上')

      expect(@acc.check_air_flow_direction_vertical(@ac)).to eq '上'
    end
  end

  describe '#check_air_flow_direction_horizontal' do
    it 'エアコンの左右風向設定を取得する' do
      allow(@acc).to receive(:ac_status).with(@ac, ttl: 1).and_return('A5' => '左')

      expect(@acc.check_air_flow_direction_horizontal(@ac)).to eq '左'
    end
  end

  describe '#check_location' do
    it 'エアコンの設置場所を取得する' do
      allow(@acc).to receive(:ac_status).with(@ac, ttl: 1).and_return('81' => '18')

      expect(@acc.check_location(@ac)).to eq 'キッチン'
    end
  end

  describe '#check_air_flow_level' do
    it 'ネットワーク内のエアコンの風量設定を取得する。風量レベルは0(静)。' do
      msg = "\x10\x81\x00\x01\x01\x30\x01\x05\xFF\x01\x72\x01\xA0\x01\x31"
      msg.force_encoding("ASCII-8BIT")
      @recv_queue << [msg, ["RSpec TEST", 3610, "", "192.168.0.250"]]
      @recv_queue << [@msg_ok, []]
      @resp_q[0].pop # recv_thread実行完了の確認

      expect(@acc.check_air_flow_level(@ac, ttl: 0)).to eq 0 # ttl:0にすることで、以後のテストでのキャッシュによる未取得を防止
    end

    it 'ネットワーク内のエアコンの風量設定を取得する。風量レベルは４(ロング)。' do
      msg = "\x10\x81\x00\x01\x01\x30\x01\x05\xFF\x01\x72\x01\xA0\x01\x35"
      msg.force_encoding("ASCII-8BIT")
      @recv_queue << [msg, ["RSpec TEST", 3610, "", "192.168.0.250"]]
      @recv_queue << [@msg_ok, []]
      @resp_q[0].pop # recv_thread実行完了の確認

      expect(@acc.check_air_flow_level(@ac, ttl: 0)).to eq 4 # ttl:0にすることで、以後のテストでのキャッシュによる未取得を防止
    end

    it 'ネットワーク内のエアコンの風量設定を取得する。風量レベルは自動設定。' do
      msg = "\x10\x81\x00\x01\x01\x30\x01\x05\xFF\x01\x72\x01\xA0\x01\x41"
      msg.force_encoding("ASCII-8BIT")
      @recv_queue << [msg, ["RSpec TEST", 3610, "", "192.168.0.250"]]
      @recv_queue << [@msg_ok, []]
      @resp_q[0].pop # recv_thread実行完了の確認

      expect(@acc.check_air_flow_level(@ac, ttl: 0)).to eq "風量自動設定" # ttl:0にすることで、以後のテストでのキャッシュによる未取得を防止
    end
  end

  describe '#change_target_temperature' do
    it '第一引数のnodeの設定温度を、第二引数で指定する温度に変更する' do
      msg = @acc.change_target_temperature(@ac, 28)
      expect(msg.seoj).to eq '05FF01'
      expect(msg.deoj).to eq '013001'
      expect(msg.esv).to eq '60'
      expect(msg.opc).to eq 1
      expect(msg.epc).to eq ["B3"]
      expect(msg.pdc).to eq [1]
      expect(msg.edt).to eq ["1C"]
    end
  end

  describe '#temp_up & temp_down' do
    before do
      msg = "\x10\x81\x00\x01\x01\x30\x01\x05\xFF\x01\x72\x01\xB3\x01\e"
      msg.force_encoding("ASCII-8BIT")
      @recv_queue << [msg, ["RSpec TEST", 3610, "", "192.168.0.250"]]
      @recv_queue << [@msg_ok, []]
      @resp_q[0].pop # recv_thread実行完了の確認
    end

    it 'temp_upをすると@temp[target_instance.ip]の値が1上がり、temp_downで1下がる' do
      @acc.temp_up(@ac)
      expect(@acc.temp[@ac.ip]).to eq 28
      @acc.temp_down(@ac)
      expect(@acc.temp[@ac.ip]).to eq 27
    end

    it '初回のtemp_upでは現在温度を取得してから1度加算する' do
      allow(@acc).to receive(:check_target_temperature).with(@ac).and_return(27)
      expect(@acc).to receive(:data_set).with(['B3'], ['1C'], @ac).and_return(:updated)

      expect(@acc.temp_up(@ac)).to eq :updated
      expect(@acc.temp[@ac.ip]).to eq 28
    end

    it '初回のtemp_downでは現在温度を取得してから1度減算する' do
      allow(@acc).to receive(:check_target_temperature).with(@ac).and_return(27)
      expect(@acc).to receive(:data_set).with(['B3'], ['1A'], @ac).and_return(:updated)

      expect(@acc.temp_down(@ac)).to eq :updated
      expect(@acc.temp[@ac.ip]).to eq 26
    end
  end

  describe '#change_operation_mode' do
    it '第一引数で指定したエアコンの運転モードを冷房にできる' do
      msg = @acc.change_operation_mode(@ac, 'Cooling')
      expect(msg.seoj).to eq '05FF01'
      expect(msg.deoj).to eq '013001'
      expect(msg.esv).to eq '60'
      expect(msg.opc).to eq 1
      expect(msg.epc).to eq ["B0"]
      expect(msg.pdc).to eq [1]
      expect(msg.edt).to eq ["42"]
    end

    it '第一引数で指定したエアコンの運転モードを暖房にできる' do
      msg = @acc.change_operation_mode(@ac, 'Heating')
      expect(msg.seoj).to eq '05FF01'
      expect(msg.deoj).to eq '013001'
      expect(msg.esv).to eq '60'
      expect(msg.opc).to eq 1
      expect(msg.epc).to eq ["B0"]
      expect(msg.pdc).to eq [1]
      expect(msg.edt).to eq ["43"]
    end

    it '第一引数で指定したエアコンの運転モードを除湿にできる' do
      msg = @acc.change_operation_mode(@ac, 'Dehumidification')
      expect(msg.seoj).to eq '05FF01'
      expect(msg.deoj).to eq '013001'
      expect(msg.esv).to eq '60'
      expect(msg.opc).to eq 1
      expect(msg.epc).to eq ["B0"]
      expect(msg.pdc).to eq [1]
      expect(msg.edt).to eq ["44"]
    end

    it '第一引数で指定したエアコンの運転モードを送風にできる' do
      msg = @acc.change_operation_mode(@ac, 'Air circulation')
      expect(msg.seoj).to eq '05FF01'
      expect(msg.deoj).to eq '013001'
      expect(msg.esv).to eq '60'
      expect(msg.opc).to eq 1
      expect(msg.epc).to eq ["B0"]
      expect(msg.pdc).to eq [1]
      expect(msg.edt).to eq ["45"]
    end

    it '未対応の運転モードを指定するとArgumentErrorになる' do
      expect do
        @acc.change_operation_mode(@ac, 'Unknown')
      end.to raise_error(ArgumentError, '対応していない運転モードです')
    end
  end
end
