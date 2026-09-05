module EchonetLiteGem
  class UDPManager
    include Singleton

    attr_reader :response_queue

    def initialize
      @tid = 0
      @closed = false

      @mutex = Mutex.new

      @udp = UDPSocket.new # udpプロパティにメインのUDPSocketを保持する。
      @udp.bind(selfip, 3610) # 自身のipアドレスの3610番ポートにbindする。
      @udp.setsockopt(Socket::IPPROTO_IP, Socket::IP_MULTICAST_IF, IPAddr.new(selfip).hton) # マルチキャスト送信時のIPアドレスを設定
      @udp.setsockopt(Socket::IPPROTO_IP, Socket::IP_MULTICAST_TTL, 1) # マルチキャストの生存時間を自ネットワーク内に留める
      @udp.setsockopt(Socket::SOL_SOCKET, Socket::SO_BROADCAST, 1) # ブロードキャスト送信を許可

      @response_queue = Hash.new { |hash, key| hash[key] = Queue.new }

      @recv_worker = Thread.new do
        recv_thread
      end
    end

    def shutdown
      return if @closed

      # recv_threadの無限ループを終了させるためのフラグ
      # 2重にshutdown処理されないためのフラグ
      @closed = true

      begin
        @udp&.close # UDPソケットを閉じる
      rescue IOError
        # ソケットのクローズ時にエラーが発生しても後続処理を続行する
      ensure
        @udp = nil
      end

      begin
        @recv_worker&.join # recv_threadが終了するまで待機
      rescue StandardError
        # join に失敗しても shutdown は継続
      ensure
        @recv_worker = nil
        @response_queue = nil
        @mutex = nil
      end

      Singleton.__init__(EchonetLiteGem::UDPManager) # シングルトンの保持している状態を初期化
    end

    def send(msg, flags, host, port)
      ensure_open!
      @udp.send(msg, flags, host, port)
    end

    # UDPソケットを使って自分のipアドレスを取得して返す。
    def selfip
      udp = UDPSocket.new
      udp.connect("128.0.0.1", 9999)
      addr = Socket.unpack_sockaddr_in(udp.getsockname)[1]
      udp.close
      addr
    rescue IOError
      udp&.close
      raise
    end

    def next_tid
      ensure_open!
      @mutex.synchronize do
        @tid += 1
        @tid &= 0xffff
        @tid
      end
    end

    private

      # 各メソッドをensure_open! で失敗させることでshutdown後の誤使用を止める
      def ensure_open!
        raise "UDPManager is closed" if @closed || @udp.nil?
      end

      def recv_thread
        loop do
          break if @closed # recv_threadの無限ループを終了させるためのフラグが立っている場合は、recv_threadを終了する

          begin
            res = @udp.recvfrom(300) # res_msgにはメッセージが、sockaddrにはソケットのアドレスが代入される
            tid = res[0][2, 2].unpack1("n") # トランザクションID
            @response_queue[tid] << res
          rescue IOError, Errno::EBADF # UDPソケットが閉じられた場合の例外処理
            break if @closed # recv_threadの無限ループを終了させるためのフラグが立っている場合は、recv_threadを終了する

            raise
          rescue Interrupt # ctrl+Cを押されたら終了
            exit
          end
        end
      end
  end
end
