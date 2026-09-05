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
      raise TelegramError, "電文は文字列で指定してください" unless telegram.is_a?(String)
      raise TelegramError, "電文が短すぎます" if telegram.bytesize < 12
      raise TelegramError, "不正なECHONET Liteヘッダーです" unless telegram.byteslice(0, 2)&.bytes == [0x10, 0x81]

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

      (0...opc).each do |i|
        property_offset = 12 + add_num
        raise TelegramError, "プロパティ電文が途中で終了しています" if property_offset + 2 > unpack_tgm.length

        epc.append unpack_tgm[property_offset, 1].pack("C").unpack1('H*').upcase # Echonetプロパティ
        pdc.append unpack_tgm[property_offset + 1] # プロパティデータカウンタ
        data_offset = property_offset + 2
        raise TelegramError, "プロパティ値データが途中で終了しています" if data_offset + pdc[i] > unpack_tgm.length

        if pdc[i].positive?
          edt.append unpack_tgm[data_offset, pdc[i]].pack("C*").unpack1('H*').upcase
        else
          edt.append nil
        end
        add_num += 2 + pdc[i]
      end

      expected_length = 12 + add_num
      raise TelegramError, "電文に余分なデータがあります" unless expected_length == unpack_tgm.length

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
