RSpec.describe EchonetLiteGem::EWHController do
  let(:udp_socket) { instance_double(UDPSocket) }

  before do
    Singleton.__init__(EchonetLiteGem::UDPManager)
    Singleton.__init__(EchonetLiteGem::EWHController)
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
    @ecc = EchonetLiteGem::EWHController.instance
    @resp_q = @ecc.instance_variable_get(:@udp).instance_variable_get(:@response_queue)
    @ecocute = EchonetLiteGem::EInstance.new(ip: '192.168.0.250', clg: '02', cls: '6B', itc: '01')
    @ecocute.release = "I"

    @msg_ok = "\x10\x81\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" # recv_thread動作完了通知用電文
    @msg_ok.force_encoding("ASCII-8BIT")
  end

  after do
    @ecc.shutdown if @ecc && (worker = @ecc.instance_variable_get(:@recv_worker)) && worker.alive?
  end

  describe '#check_water_amount' do
    before do
      msg = "\x10\x81\x00\x01\x02\x6b\x01\x05\xFF\x01\x72\x01\xE1\x02\x00\xC8"
      msg.force_encoding("ASCII-8BIT")
      @recv_queue << [msg, ["RSpec TEST", 3610, "", "192.168.0.250"]]
      @recv_queue << [@msg_ok, []]
      @resp_q[0].pop # recv_thread実行完了の確認
    end

    # it '取得した残湯量計測値をデータベースに保存するためsave_dataメソッドを呼び出す' do
    #   expect(@ecc).to receive(:save_data)
    #   @ecc.check_water_amount(@ecocute)
    # end

    it 'ネットワーク内のエコキュートから残湯量計測値を取得する' do
      allow(@ecc).to receive(:save_data)
      expect(@ecc.check_water_amount(@ecocute, ttl: 0)).to eq 200
    end
  end

  describe '#ewh_status' do
    it 'エコキュートの状態取得に必要なEPCをまとめて問い合わせる' do
      epc = %w[B0 B2 B4 C0 D1 D3 E1 E3 EA EE]
      allow(@ecc).to receive(:cached_data_get).with(epc, @ecocute, ttl: 7).and_return('E1' => 200)

      expect(@ecc.check_water_amount(@ecocute, ttl: 7)).to eq 200
      expect(@ecc).to have_received(:cached_data_get).with(epc, @ecocute, ttl: 7)
    end
  end

  describe '#check_automatic_water_heating' do
    before do
      msg = "\x10\x81\x00\x01\x02\x6b\x01\x05\xFF\x01\x72\x01\xB0\x01\x41"
      msg.force_encoding("ASCII-8BIT")
      @recv_queue << [msg, ["RSpec TEST", 3610, "", "192.168.0.250"]]
      @recv_queue << [@msg_ok, []]
      @resp_q[0].pop # recv_thread実行完了の確認
    end

    it 'ネットワーク内のエコキュートから沸き上げ自動設定の状態を取得する' do
      expect(@ecc.check_automatic_water_heating(@ecocute, ttl: 0)).to eq '自動沸き上げ'
    end
  end

  describe '#check_water_heater_status' do
    it 'エコキュートの沸き上げ中状態を取得する' do
      allow(@ecc).to receive(:ewh_status).with(@ecocute, ttl: 1).and_return('B2' => '沸き上げ中')

      expect(@ecc.check_water_heater_status(@ecocute)).to eq '沸き上げ中'
    end
  end

  describe '#check_heating_stop_days' do
    it 'エコキュートの手動沸き上げ停止日数を取得する' do
      allow(@ecc).to receive(:ewh_status).with(@ecocute, ttl: 1).and_return('B4' => 3)

      expect(@ecc.check_heating_stop_days(@ecocute)).to eq 3
    end
  end

  describe '#check_daytime_reheating_permission' do
    it 'エコキュートの昼間沸き増し許可設定を取得する' do
      allow(@ecc).to receive(:ewh_status).with(@ecocute, ttl: 1).and_return('C0' => '許可')

      expect(@ecc.check_daytime_reheating_permission(@ecocute)).to eq '許可'
    end
  end

  describe '#check_hot_water_supply_status' do
    it '給湯中状態を取得する' do
      allow(@ecc).to receive(:ewh_status).with(@ecocute, ttl: 1).and_return('C3' => '給湯中')

      expect(@ecc.check_hot_water_supply_status(@ecocute)).to eq '給湯中'
    end
  end

  describe '#check_energy_shift_participation' do
    it 'エネルギーシフト参加状態を取得する' do
      allow(@ecc).to receive(:ewh_status).with(@ecocute, ttl: 1).and_return('C7' => '参加')

      expect(@ecc.check_energy_shift_participation(@ecocute)).to eq '参加'
    end
  end

  describe '#check_standard_time_to_start_heating' do
    it '沸き上げ開始時刻を取得する' do
      allow(@ecc).to receive(:ewh_status).with(@ecocute, ttl: 1).and_return('C8' => '23:00')

      expect(@ecc.check_standard_time_to_start_heating(@ecocute)).to eq '23:00'
    end
  end

  describe '#check_number_of_energy_shifts' do
    it 'エネルギーシフト回数を取得する' do
      allow(@ecc).to receive(:ewh_status).with(@ecocute, ttl: 1).and_return('C9' => 3)

      expect(@ecc.check_number_of_energy_shifts(@ecocute)).to eq 3
    end
  end

  describe '#check_water_heating_shift_time1' do
    it '昼間沸き上げ開始時刻1を取得する' do
      allow(@ecc).to receive(:ewh_status).with(@ecocute, ttl: 1).and_return('CA' => '12:00')

      expect(@ecc.check_water_heating_shift_time1(@ecocute)).to eq '12:00'
    end
  end

  describe '#check_estimated_electric_energy_at_shift_time1' do
    it '沸き上げ予測電力量を取得する' do
      allow(@ecc).to receive(:ewh_status).with(@ecocute, ttl: 1).and_return('CB' => 1.5)

      expect(@ecc.check_estimated_electric_energy_at_shift_time1(@ecocute)).to eq 1.5
    end
  end

  describe '#check_electric_energy_consukption_rate1' do
    it '時間あたり消費電力量を取得する' do
      allow(@ecc).to receive(:ewh_status).with(@ecocute, ttl: 1).and_return('CC' => 2.5)

      expect(@ecc.check_electric_energy_consukption_rate1(@ecocute)).to eq 2.5
    end
  end

  describe '#check_target_supplied_water_temperature' do
    it '給湯温度設定値を取得する' do
      allow(@ecc).to receive(:ewh_status).with(@ecocute, ttl: 1).and_return('D1' => 42)

      expect(@ecc.check_target_supplied_water_temperature(@ecocute)).to eq 42
    end
  end

  describe '#check_target_bath_water_temperature' do
    it '風呂温度設定値を取得する' do
      allow(@ecc).to receive(:ewh_status).with(@ecocute, ttl: 1).and_return('D3' => 40)

      expect(@ecc.check_target_bath_water_temperature(@ecocute)).to eq 40
    end
  end

  describe '#check_automatic_bath_operation' do
    it '風呂自動モード設定を取得する' do
      allow(@ecc).to receive(:ewh_status).with(@ecocute, ttl: 1).and_return('E3' => '自動')

      expect(@ecc.check_automatic_bath_operation(@ecocute)).to eq '自動'
    end
  end

  describe '#check_bath_operation_status_monitor' do
    it '風呂動作状態監視を取得する' do
      allow(@ecc).to receive(:ewh_status).with(@ecocute, ttl: 1).and_return('EA' => '停止')

      expect(@ecc.check_bath_operation_status_monitor(@ecocute)).to eq '停止'
    end
  end

  describe '#check_bath_water_volume3' do
    it '風呂湯量設定3を取得する' do
      allow(@ecc).to receive(:ewh_status).with(@ecocute, ttl: 1).and_return('EE' => 180)

      expect(@ecc.check_bath_water_volume3(@ecocute)).to eq 180
    end
  end

  describe '#change_automatic_water_heating' do
    it '送信したETelegramインスタンスのメッセージが正しい電文になっている' do
      msg = @ecc.change_automatic_water_heating(@ecocute, "auto")
      expect(msg.seoj).to eq '05FF01'
      expect(msg.deoj).to eq '026B01'
      expect(msg.esv).to eq '60'
      expect(msg.opc).to eq 1
      expect(msg.epc).to eq ["B0"]
      expect(msg.pdc).to eq [1]
      expect(msg.edt).to eq ["41"]
    end

    it '手動沸き上げに変更するとEDTが42になる' do
      expect(@ecc.change_automatic_water_heating(@ecocute, "manualHeating").edt).to eq ["42"]
    end

    it '手動停止に変更するとEDTが43になる' do
      expect(@ecc.change_automatic_water_heating(@ecocute, "manualNoHeating").edt).to eq ["43"]
    end

    it '未対応の状態を指定するとArgumentErrorになる' do
      expect do
        @ecc.change_automatic_water_heating(@ecocute, 'unknown')
      end.to raise_error(ArgumentError, '対応していない沸き上げ設定です')
    end
  end
end
