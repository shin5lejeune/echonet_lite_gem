RSpec.describe EchonetLiteGem::EchonetNode do
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
    allow(udp_socket).to receive(:recvfrom) do
      value = @recv_queue.pop
      raise value if value.is_a?(Exception)

      value
    end
    allow(Socket).to receive(:getifaddrs).and_return([double('ifaddr',
                                                             addr: double('addr', ipv4?: true, ip_address: "192.168.0.11"),
                                                             broadaddr: double('baddr', ip_address: "192.168.0.255"))])
    allow_any_instance_of(EchonetLiteGem::UDPManager).to receive(:selfip).and_return('192.168.0.11')
    @en = EchonetLiteGem::EchonetNode.new
    @msg = "\x10\x81\x00\x64\x02\x6B\x01\x05\xFF\x01\x72\x02\xE1\x02\x00\x64\xE2\x02\x01\x90" # エコキュートからの返答電文
    @msg.force_encoding("ASCII-8BIT")
    @telegram = EchonetLiteGem::ETelegram.new(
      tid: 100,
      seoj: '026B01',
      deoj: '05FF01',
      esv: '72',
      opc: 2,
      epc: %w[E1 E2],
      pdc: [2, 2],
      edt: %w[0064 0190]
    )
  end

  after do
    @en.shutdown if @en && (worker = @en.instance_variable_get(:@recv_worker)) && worker.alive?
  end

  describe '#shutdown' do
    it "udp_managerのshutdownメソッドを呼び出す" do
      udp = @en.instance_variable_get(:@udp)
      expect(udp).to receive(:shutdown)
      @en.shutdown
    end
  end

  describe '#read' do
    describe '引数にECHONET LiteのUDPペイロードの電文("\x10\x81\x00...")を受け取ってETelegramを生成する' do
      it "ETlegramを返す" do
        allow(Kernel).to receive(:print)
        expect(@en.read(@msg)).to be_an_instance_of(EchonetLiteGem::ETelegram)
      end

      it "生成したETelegramからmake_telegramメソッドで電文を再生成しても元の電文と一致する" do
        expect(@en.read(@msg).make_telegram).to eq @msg
      end
    end
  end

  describe '#send' do
    before do
      @incomplete_telegram = EchonetLiteGem::ETelegram.new
      @ei = EchonetLiteGem::EInstance.new ip: "192.168.0.20", clg: '02', cls: '6B', itc: '01'
    end

    describe '第一引数に指定したETelegramを、第二引数に指定したEInstanceにUDP送信。' do
      it "正しい引数(メッセージ, フラグ通常0, ホスト, ポート)でUDPSocket.sendメソッドが呼ばれる" do
        expect(udp_socket).to receive(:send).with(@msg, 0, "192.168.0.20", "3610")
        @en.send(@telegram, @ei)
      end

      it "sendメソッドで、未完成のETelegramを渡すとエラー発生して終了する" do
        expect { @en.send(@incomplete_telegram, @ei) }.to raise_error "送信元オブジェクトが指定されていません"
      end
    end

    describe '第二引数には"broadcast"か、"multicast"を指定することも可能' do
      it "第二引数に'broadcast'を指定すると、マルチキャストアドレスとブロードキャストアドリスの両方に送信する" do
        expect(udp_socket).to receive(:send).with(@msg, 0, "224.0.23.0", "3610")
        expect(udp_socket).to receive(:send).with(@msg, 0, "192.168.0.255", "3610")
        @en.send(@telegram, 'broadcast')
      end

      it "第二引数に'multicast'を指定すると、マルチキャストアドレス(224.0.23.0)に送信する" do
        expect(udp_socket).to receive(:send).with(@msg, 0, "224.0.23.0", "3610")
        @en.send(@telegram, 'multicast')
      end
    end
  end
end
