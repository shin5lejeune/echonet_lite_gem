RSpec.describe EchonetLiteGem::UDPManager do
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
    allow(udp_socket).to receive(:getsockname).and_return('sockaddr')
    allow(udp_socket).to receive(:recvfrom) do
      value = @recv_queue.pop
      raise value if value.is_a?(Exception)

      value
    end
    allow(Socket).to receive(:unpack_sockaddr_in).with('sockaddr').and_return([3610, '192.168.0.12'])
    allow(Socket).to receive(:getifaddrs).and_return([double('ifaddr',
                                                             addr: double('addr', ipv4?: true, ip_address: "192.168.0.11"),
                                                             broadaddr: double('baddr', ip_address: "192.168.0.255"))])
    allow_any_instance_of(EchonetLiteGem::UDPManager).to receive(:selfip).and_return('192.168.0.11')
    @udp_m = EchonetLiteGem::UDPManager.instance
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
    @udp_m.shutdown if @udp_m && (worker = @udp_m.instance_variable_get(:@recv_worker)) && worker.alive?
  end

  describe "ECHONET Liteの機能を提供するベースクラス" do
    # it "power_stateで電源状態を保持し、初期状態はtrue" do
    #   expect(@udp_m.power_state).to eq true
    # end

    it "singletonパターンでインスタンスを生成する" do
      expect(EchonetLiteGem::UDPManager.instance).to be_an_instance_of(EchonetLiteGem::UDPManager)
    end

    it "starts a real recv thread" do
      expect(@udp_m.instance_variable_get(:@recv_worker)).to be_alive
    end
  end

  describe '#shutdown' do
    describe 'UDPManagerインスタンスの終了メソッド。UDPソケットを閉じ、recv_workerを終了し、シングルトン内部で保持しているインスタンスをリセット'
    it 'UDPSocketのcloseメソッドが呼ばれる' do
      expect(udp_socket).to receive(:close)

      @udp_m.shutdown
    end

    it 'recv_workerが終了する' do
      worker = @udp_m.instance_variable_get(:@recv_worker)
      expect(worker).to be_alive

      @udp_m.shutdown

      expect(worker).not_to be_alive
    end

    describe 'シングルトン内部で保持しているインスタンスがリセットされる' do
      it 'closeする前にはシングルトン内部にインスタンスが保持されている' do
        expect(EchonetLiteGem::UDPManager.instance_variable_get(:@singleton__instance__)).not_to be_nil
      end
      it 'closeメソッド呼び出し後には、シングルトン内部にインスタンスが無い' do
        @udp_m.shutdown

        expect(EchonetLiteGem::UDPManager.instance_variable_get(:@singleton__instance__)).to be_nil
      end
      it 'closeメソッド呼び出し後にインスタンスを再生成すると、再びシングルトン内部にインスタンスが保持される' do
        @udp_m.shutdown

        node = EchonetLiteGem::UDPManager.instance
        expect(EchonetLiteGem::UDPManager.instance_variable_get(:@singleton__instance__)).not_to be_nil
        node.shutdown
      end

      it 'closeメソッド呼び出し後に再生成したインスタンスは別物になっている' do
        original_instance = @udp_m

        @udp_m.shutdown

        node = EchonetLiteGem::UDPManager.instance
        expect(node).not_to eq original_instance
        node.shutdown
      end
    end

    it 'IOErrorが発生しても、close処理は完了し、再びEchonetLiteGem::UDPManager.instanceすればでリセット可能' do
      allow(udp_socket).to receive(:close) do
        @recv_queue << IOError.new
        raise IOError
      end
      worker = @udp_m.instance_variable_get(:@recv_worker)

      expect(udp_socket).to receive(:close)
      expect { @udp_m.shutdown }.not_to raise_error
      expect(worker).not_to be_alive
      expect(EchonetLiteGem::UDPManager.instance_variable_get(:@singleton__instance__)).to be_nil

      node = EchonetLiteGem::UDPManager.instance
      expect(node).to be_an_instance_of(EchonetLiteGem::UDPManager)
      node.shutdown
    end

    describe '一度shutdownメソッドを呼ぶと、closedプロパティがtrueになり、二重shutdownを防ぐ' do
      it 'closedプロパティがtrueになる' do
        expect(@udp_m.instance_variable_get(:@closed)).to eq false

        @udp_m.shutdown

        expect(@udp_m.instance_variable_get(:@closed)).to eq true
      end

      it '２回目の呼び出しでは、Singleton.__init__()は呼ばれない' do
        expect(Singleton).to receive(:__init__)

        @udp_m.shutdown

        expect(Singleton).not_to receive(:__init__)

        @udp_m.shutdown
      end
    end

    describe '保持している各情報をnilにする' do
      it '@udpがnilになる' do
        expect(@udp_m.instance_variable_get(:@udp)).not_to be_nil

        @udp_m.shutdown

        expect(@udp_m.instance_variable_get(:@udp)).to be_nil
      end
      it '@recv_workerがnilになる' do
        expect(@udp_m.instance_variable_get(:@recv_worker)).not_to be_nil

        @udp_m.shutdown

        expect(@udp_m.instance_variable_get(:@recv_worker)).to be_nil
      end
      it '@response_queueがnilになる' do
        expect(@udp_m.instance_variable_get(:@response_queue)).not_to be_nil

        @udp_m.shutdown

        expect(@udp_m.instance_variable_get(:@response_queue)).to be_nil
      end
      it '@mutexがnilになる' do
        expect(@udp_m.instance_variable_get(:@mutex)).not_to be_nil

        @udp_m.shutdown

        expect(@udp_m.instance_variable_get(:@mutex)).to be_nil
      end
    end
  end

  describe '#next_tid' do
    it 'トランザクションIDを1から順番に返す' do
      expect(@udp_m.next_tid).to eq 1
      expect(@udp_m.next_tid).to eq 2
    end

    it 'トランザクションIDが65535の次に0へ折り返す' do
      @udp_m.instance_variable_set(:@tid, 0xffff)

      expect(@udp_m.next_tid).to eq 0
    end

    it 'shutdown後に呼び出すとエラーになる' do
      @udp_m.shutdown

      expect { @udp_m.next_tid }.to raise_error 'UDPManager is closed'
    end
  end

  describe '#send' do
    it '指定したメッセージ、フラグ、ホスト、ポートでUDPSocketに送信する' do
      expect(udp_socket).to receive(:send).with(@msg, 0, '192.168.0.20', '3610')

      @udp_m.send(@msg, 0, '192.168.0.20', '3610')
    end

    it 'UDPSocketの送信結果を返す' do
      allow(udp_socket).to receive(:send).and_return(@msg.bytesize)

      expect(@udp_m.send(@msg, 0, '192.168.0.20', '3610')).to eq @msg.bytesize
    end

    it 'shutdown後に呼び出すとエラーになる' do
      @udp_m.shutdown

      expect { @udp_m.send(@msg, 0, '192.168.0.20', '3610') }.to raise_error 'UDPManager is closed'
    end
  end

  # describe '#read' do
  #   describe '引数にECHONET LiteのUDPペイロードの電文("\x10\x81\x00...")を受け取ってETelegramを生成する' do
  #     it "ETlegramを返す" do
  #       allow(Kernel).to receive(:print)
  #       expect(@udp_m.read(@msg)).to be_an_instance_of(EchonetLiteGem::ETelegram)
  #     end

  #     it "生成したETelegramからmake_telegramメソッドで電文を再生成しても元の電文と一致する" do
  #       expect(@udp_m.read(@msg).make_telegram).to eq @msg
  #     end
  #   end
  # end

  # describe '#send' do
  #   before do
  #     @incomplete_telegram = EchonetLiteGem::ETelegram.new
  #     @ei = EchonetLiteGem::EInstance.new ip: "192.168.0.20", clg: '02', cls: '6B', itc: '01'
  #   end

  #   describe '第一引数に指定したETelegramを、第二引数に指定したEInstanceにUDP送信。' do
  #     it "正しい引数(メッセージ, フラグ通常0, ホスト, ポート)でUDPSocket.sendメソッドが呼ばれる" do
  #       expect(udp_socket).to receive(:send).with(@msg, 0, "192.168.0.20", "3610")
  #       @udp_m.send(@telegram, @ei)
  #     end

  #     it "sendメソッドで、未完成のETelegramを渡すとエラー発生して終了する" do
  #       expect { @udp_m.send(@incomplete_telegram, @ei) }.to raise_error "送信元オブジェクトが指定されていません"
  #     end
  #   end

  #   describe '第二引数には"broadcast"か、"multicast"を指定することも可能' do
  #     it "第二引数に'broadcast'を指定すると、マルチキャストアドレスとブロードキャストアドリスの両方に送信する" do
  #       expect(udp_socket).to receive(:send).with(@msg, 0, "224.0.23.0", "3610")
  #       expect(udp_socket).to receive(:send).with(@msg, 0, "192.168.0.255", "3610")
  #       @udp_m.send(@telegram, 'broadcast')
  #     end

  #     it "第二引数に'multicast'を指定すると、マルチキャストアドレス(224.0.23.0)に送信する" do
  #       expect(udp_socket).to receive(:send).with(@msg, 0, "224.0.23.0", "3610")
  #       @udp_m.send(@telegram, 'multicast')
  #     end
  #   end
  # end

  describe '#selfip' do
    it '自身のIPアドレスIPアドレス（e.g. "192.168.0.12"）を返す' do
      allow(@udp_m).to receive(:selfip).and_call_original
      allow(udp_socket).to receive(:recvfrom)

      expect(@udp_m.selfip).to eq '192.168.0.12'
    end

    it '接続時にIOErrorが発生するとソケットを閉じて例外を返す' do
      selfip_socket = instance_double(UDPSocket)
      allow(@udp_m).to receive(:selfip).and_call_original
      allow(UDPSocket).to receive(:new).and_return(selfip_socket)
      allow(selfip_socket).to receive(:connect).and_raise(IOError)
      expect(selfip_socket).to receive(:close)

      expect { @udp_m.selfip }.to raise_error(IOError)
    end
  end

  describe 'recv_worker' do
    it 'recv_workerは、UDPSocketのrecvメソッドで電文を受信し、response_queueハッシュのtidをキーとした要素のqueueに入れる' do
      response_queue = @udp_m.instance_variable_get(:@response_queue)[@telegram.tid]
      @recv_queue << [@msg, 'sockaddr']

      received = nil
      wait = 0
      while wait < 1
        begin
          received = response_queue.pop(true)
          break
        rescue ThreadError
          sleep 0.01
          wait += 0.01
        end
      end

      expect(received).to eq [@msg, 'sockaddr']
    end

    it '1つのTIDのキューには最大件数(128)を超えて保持しない' do
      manager = @udp_m
      response = [@msg, 'sockaddr']

      129.times do
        manager.__send__(:enqueue_response, @telegram.tid, response)
      end

      queue = manager.response_queue[@telegram.tid]
      expect(queue.size).to eq EchonetLiteGem::UDPManager::MAX_QUEUE_SIZE
    end

    it 'TIDごとのキュー数の上限は4096件' do
      manager = @udp_m
      response = [@msg, 'sockaddr']

      4097.times do |tid|
        manager.__send__(:enqueue_response, tid, response)
      end

      expect(manager.response_queue.size).to eq EchonetLiteGem::UDPManager::MAX_RESPONSE_QUEUES
      expect(manager.response_queue).not_to have_key(EchonetLiteGem::UDPManager::MAX_RESPONSE_QUEUES)
    end
  end

  describe '#recv_thread' do
    it 'shutdown前の予期しないIOErrorを再送出する' do
      manager = EchonetLiteGem::UDPManager.send(:allocate)
      manager.instance_variable_set(:@closed, false)
      manager.instance_variable_set(:@udp, udp_socket)
      allow(udp_socket).to receive(:recvfrom).and_raise(IOError)

      expect { manager.__send__(:recv_thread) }.to raise_error(IOError)
    end
  end
end
