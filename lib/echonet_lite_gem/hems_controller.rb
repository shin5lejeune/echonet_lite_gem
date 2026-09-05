module EchonetLiteGem
  class HEMSController < EchonetNode
    attr_reader :target_instances
    attr_writer :target_node_eoj

    @@instance_no = 1
    def initialize
      super
      @eoj = ""
      @instance_no = @@instance_no
      @@instance_no += 1
      @eoj = "05FF#{[@instance_no].pack("C").unpack1("H*").upcase}"
      @target_node_eoj = ""
      @code_json = AssetLoader.load_json("code.json") # code.jsonファイルを取得してparse
      @company_code_json = AssetLoader.load_json("company_code.json") # company_code.jsonファイルを取得してparse

      @power_mutex = Mutex.new
    end

    # デバイスノードの検索して、EInstanceの配列を返す
    def search(cast = "multicast")
      send_t = ETelegram.new(seoj: @eoj, deoj: "0EF001", esv: "62", opc: 1, epc: ["D6"], pdc: [0])
      if cast == "multicast"
        send(send_t, "multicast")
      elsif cast == "broadcast"
        send(send_t, "broadcast")
      end
      instance_ary = []
      res = nil
      loop do
        # 以下一行はRSpecでテストする際に無限ループ回避するためのコード
        raise Timeout::Error unless res.nil? || res[1][0] != "RSpec TEST"

        Timeout.timeout(0.5) do # 0.5秒通信が途絶えたら終了する
          res = @udp.response_queue[send_t.tid].pop # res_msgにはメッセージが、sockaddrにはソケットのアドレスが代入される
        end
        res_t = read(res[0])

        res_t.epc.each_with_index do |epc, i|
          # EPCが'd6' や 'D6' の場合は受け付ける
          next unless epc.to_s.upcase == "D6"

          edt = res_t.edt[i]
          itc_num = edt[0, 2].to_i(16)
          (0..(itc_num - 1)).each do |num|
            instance_ary.append(EInstance.new(ip: res[1][3],
                                              clg: edt[2 + (num * 3), 2], # クラスグループコード　string
                                              cls: edt[4 + (num * 3), 2], # クラスコード　string
                                              itc: edt[6 + (num * 3), 2])) # インスタンスコード　string
          end
        end
      rescue Timeout::Error
        break
      end
      instance_ary.each do |e_instance|
        check_release_version e_instance
      end
      @target_instances = instance_ary
    end

    # ネットワーク内にある担当するECHONETオブジェクトの配列を返す
    def target_nodes(cast = "multicast")
      ei_ary = search(cast)
      ei_ary.select! do |ei|
        # target_node_eojが指定されている場合は、target_node_eojと一致するノードのみを対象とする
        # target_node_eojが空文字列の場合は、全てのノードを対象とする
        @target_node_eoj == (ei.clg + ei.cls) || @target_node_eoj == ""
      end
      @target_instances = ei_ary
    end

    # データを取得したいプロパティの配列と、相手のEInstanceを指定して、edt_hashの形でデータを取得して返す
    def data_get(epc, target_instance, node_profile: false)
      raise(StandardError.new, "epcはArrayを指定して下さい") unless epc.is_a? Array
      raise(StandardError.new, "target_instanceが正しく指定されていません") unless target_instance.is_a? EInstance

      pdc = []
      epc.length.times { pdc << 0 } # データ問い合わせ時の電文のedtは不要なので、pdcは全て0にする。
      # ETelegramの作成
      deoj = node_profile ? "0EF001" : target_instance.eoj
      send_t = ETelegram.new(seoj: @eoj, deoj: deoj, esv: "62", opc: epc.length, epc: epc, pdc: pdc)

      # 相手ノードからの返答を5秒まで待つ。5秒以上返答ない場合は２回までリトライする。
      retry_count = 0
      while retry_count < 3
        send(send_t, target_instance) # ETelegramを送信
        # Timeoutエラーを例外処理
        begin
          res_msg = ""
          Timeout.timeout(3) do # 3秒経ったらタイムアウトする
            res_msg, _sockaddr = @udp.response_queue[send_t.tid].pop # res_msgにはメッセージが、sockaddrにはソケットのアドレスが代入される
          end
        rescue Timeout::Error # Timeoutエラーを例外処理
          retry_count += 1
          puts "data_get time out : #{retry_count}回目"
          next
        rescue Interrupt # ctrl+Cを押されたら終了
          return {}
        end
        res_t = read(res_msg) # 返信されたtelegramを解読してETelegramに変換

        target_instance.release ||= "A" if epc == ["82"] # releaseプロパティが未設定の時のcheck_release_versionの無限ループを防止
        target_instance.release ||= check_release_version(target_instance) # releaseプロパティが未設定の時は相手Nodeに問い合わせる

        res_hash = res_t.edt_hash(target_instance.release)
        if epc == ["82"]
          # target_instanceのreleaseバージョンが、上記無限ループ対策で仮設定した"A"のままになるのを防止
          target_instance.release = [res_hash["82"][4, 2]].pack("H*")
        else
          res_hash.each do |epc, edt| # 返信されたtelegramのedtのハッシュごとに、内容を標準出力に出力
            puts "#{target_instance.get_epc_name(epc)}:#{edt}"
          end
        end

        return res_hash
      end
      {}
    end

    # データを設定したいプロパティの配列と、設定したいデータの配列、相手のEInstanceを指定して、ノードへUDP送信する。戻り値は、ETelegram.
    def data_set(epc, edt, target_instance)
      raise(StandardError.new, "epcはArrayを指定して下さい") unless epc.is_a? Array
      raise(StandardError.new, "edtはArrayを指定して下さい") unless edt.is_a? Array
      raise(StandardError.new, "epcとedtの要素数を一致させて下さい") unless epc.length == edt.length
      raise(StandardError.new, "target_instanceにはEInstanceを指定して下さい") unless target_instance.is_a?(EInstance)
      raise(StandardError.new, "edtは文字列の配列を指定して下さい") unless edt.all?(String)
      raise(StandardError.new, "edtは偶数桁の16進数文字列を指定して下さい") unless edt.all? { |value| /^(\h{2})+$/.match?(value) }

      pdc = []
      edt.each do |e|
        n = e.length / 2
        pdc << n
      end
      send_t = ETelegram.new(seoj: "05FF01", deoj: target_instance.eoj, esv: "60", opc: epc.length, epc: epc, pdc: pdc,
                             edt: edt)
      send(send_t, target_instance) # ETelegramを送信

      # 書き込み後は古い値が残らないようにキャッシュを無効化する
      cache_key = "#{target_instance.ip}:#{target_instance.eoj}:#{epc.join(",")}"
      @data_cache ||= {}
      @data_cache[cache_key] = nil

      send_t
    end

    # 以下superクラスのEPCの操作メソッド
    def check_power_state(target_instance)
      data_get(["80"], target_instance)["80"]
    end

    def power_on(target_instance)
      @power_mutex.synchronize do
        data_set(["80"], ["30"], target_instance)
      end
    end

    def power_off(target_instance)
      @power_mutex.synchronize do
        data_set(["80"], ["31"], target_instance)
      end
    end

    # 現在の電源の状態に応じて、ON/OFFを切り替える
    def change_power_state(target_instance)
      @power_mutex.synchronize do
        check_power_state(target_instance) == 'ON' ? power_off(target_instance) : power_on(target_instance)
      end
    end

    def check_release_version(target_instance)
      target_instance.release = [data_get(["82"], target_instance)["82"][4, 2]].pack("H*")
    end

    # data_get のキャッシュラッパー
    #
    # 対象 EInstance とプロパティの組み合わせごとに応答を ttl 秒間保存し、
    # その期間内の繰り返し参照で UDP を再送しないようにします。
    def cached_data_get(epc, target_instance, ttl: 1)
      cache_key = "#{target_instance.ip}:#{target_instance.eoj}:#{epc.join(",")}"
      @data_cache ||= {}
      cache = @data_cache[cache_key]
      return cache[:response] if cache && cache[:expires_at] > Time.now

      response = data_get(epc, target_instance)
      @data_cache[cache_key] = { response: response, expires_at: Time.now + ttl }
      response
    end

    def check_manufacturer(target_instance)
      company_code = data_get(["8A"], target_instance)["8A"]
      @company_code_json.each do |company|
        return company["company"] if company_code == company["code"]
      end
      nil
    end

    def check_product_code(target_instance, node_profile: false)
      [data_get(["8C"], target_instance, node_profile: node_profile)["8C"]].pack("H*").strip
    end

    def check_location(target_instance)
      edt = data_get(["81"], target_instance)["81"]
      location_code = (edt.to_i(16) & "f8".to_i(16)).to_s(16)
      location_code.size == 2 || location_code = "0#{location_code}"
      @code_json["location"]["0x#{location_code}"]
    end
  end
end
