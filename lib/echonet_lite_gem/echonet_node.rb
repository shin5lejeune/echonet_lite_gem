module EchonetLiteGem
  class EchonetNode
    def initialize
      @udp = EchonetLiteGem::UDPManager.instance
    end

    def shutdown
      @udp.shutdown
    end

    # 引数に指定したUDP電文をETelegramに変換
    def read(telegram)
      unpack_tgm = telegram.unpack("C*")
      ehd1 = unpack_tgm[0, 1].pack("C") # 伝聞ヘッダー１　ECHONET Lite
      ehd2 = unpack_tgm[1, 1].pack("C") # 伝聞ヘッダー２　規定電文形式
      tid = unpack_tgm[2, 2].pack("C*").unpack1("S>") # トランザクションID
      seoj = unpack_tgm[4, 3].pack("C*").unpack1('H*').upcase # 送信元　クラスグループ、クラス、インスタンスコード
      deoj = unpack_tgm[7, 3].pack("C*").unpack1('H*').upcase # 相手先　クラスグループ、クラス、インスタンスコード
      esv = unpack_tgm[10, 1].pack("C").unpack1('H*').upcase # ECHONET Liteサービス
      opc = unpack_tgm[11] # 処理プロパティ数
      epc = []
      pdc = []
      edt = []
      add_num = 0
      (0..(opc - 1)).each do |i|
        epc.append unpack_tgm[12 + add_num, 1].pack("C").unpack1('H*').upcase # Echonetプロパティ
        pdc.append unpack_tgm[13 + add_num] # プロパティデータカウンタ
        if pdc[i].positive?
          edt.append unpack_tgm[14 + add_num, pdc[i]].pack("C*").unpack1('H*').upcase
        else
          edt.append nil
        end
        add_num += 2 + pdc[i]
      end
      ETelegram.new ehd1:, ehd2:, tid:, seoj:, deoj:, esv:, opc:, epc:, pdc:, edt:
    end

    # 引数に指定したETelegramを、指定したEInstanceに送信。output:trueとすると送信元のUDPSocketを返す。
    def send(telegram, target_instance)
      unless target_instance == "multicast" || target_instance == "broadcast" || target_instance.is_a?(EInstance)
        raise(InstanceError.new, '#sendの第二引数はEInstanceもしくは、"multicast"か"broadcast"を設定して下さい')
      end

      msg = telegram.make_telegram(tid: @udp.next_tid) # UDP通信の電文

      case target_instance
      when "broadcast" # broadcast指定の場合、マルチキャストアドレスとブロードキャストアドリスの両方に送信
        # ブロードキャストアドレスを取得するために、ネットワークインターフェースの情報を取得して、指定したIPアドレスに対応するブロードキャストアドレスを見つける
        broadcast_ip = Socket.getifaddrs.find { |x| x.addr.ipv4? and x.addr.ip_address == @udp.selfip }.broadaddr.ip_address
        @udp.send msg, 0, "224.0.23.0", "3610" # マルチキャスト
        @udp.send msg, 0, broadcast_ip, "3610" # ブロードキャスト
      when "multicast" # マルチキャストアドレス値は224.9.23.0
        @udp.send msg, 0, "224.0.23.0", "3610"
      else
        @udp.send msg, 0, target_instance.ip, "3610"
      end
    end
  end
end
