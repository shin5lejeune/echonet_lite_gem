module EchonetLiteGem
  class EInstance
    attr_accessor :release
    attr_reader :ip, :clg, :cls, :itc, :device_json, :super_class_json

    # ip,class_gloup_code, class_code, instance_codeは、必須
    def initialize(ip:, clg:, cls:, itc:)
      @ip = ip # string
      @clg = clg # クラスグループコード　string
      @cls = cls # クラスコード　string
      @itc = itc # インスタンスコード　string
      @def_json = AssetLoader.load_json("mraData/definitions/definitions.json") # definitions.jsonのjsonファイルを取得
      @node_profile_json = AssetLoader.load_json("mraData/nodeProfile/0x0EF0.json") # nodeProfileのjsonファイルを取得
      @node_profile_json.merge!(@def_json) # node_profile_jsonにdefinitions.jsonをマージする
      JsonRefs.call(@node_profile_json) # node_profile_jsonの中の$refを展開して、rubyハッシュに変換する
      @super_class_json = AssetLoader.load_json("mraData/superClass/0x0000.json") # superClassのjsonファイルを取得
      @super_class_json.merge!(@def_json) # super_class_jsonにdefinitions.jsonをマージする
      JsonRefs.call(@super_class_json) # super_class_jsonの中の$refを展開して、rubyハッシュに変換する
      @device_json ||= make_device_json # 該当するEOJクラスコードのjsonを選択して、rubyハッシュにparse
    end

    # 3バイトのエコーネットオブジェクトを文字列で返す
    def eoj
      @clg + @cls + @itc
    end

    # 自分のインスタンス情報を出力
    def data
      { 'IPアドレス' => @ip,
        'オブジェクト' => @device_json['className']['ja'],
        'インスタンスID' => @itc,
        'Releaseバージョン' => @release }
    end

    # 自分のインスタンス情報を出力
    def print_data
      d = data
      print_data = <<~DATA
        ipアドレス：#{d['IPアドレス']}
        オブジェクト：#{d['オブジェクト']}
        インスタンスID：#{d['インスタンスID']}
        Releaseバージョン：#{d['Releaseバージョン']}
      DATA
      print print_data
    end

    # プロパティ一覧をjsonファイルから取得して、epcとプロパティ名と説明のハッシュの配列として出力
    def epc_list
      raise(InstanceError.new, "releaseバージョンが設定されていません") if @release.nil?

      @device_json ||= make_device_json
      properties = @super_class_json['elProperties'].concat(@device_json['elProperties'])
      p_ary = []
      node_p_ary = []
      properties.each do |property|
        # releaseバージョンの一致を確認
        release_from = property['validRelease']['from'].unpack1("C")
        release_to = property['validRelease']['to'].unpack1("C")
        next unless @release.unpack1("C").between?(release_from, release_to)

        p_ary <<
          { epc: property["epc"], name: property["propertyName"]["ja"], description: property["descriptions"]["ja"] }
      end
      @node_profile_json['elProperties'].each do |property|
        # releaseバージョンの一致を確認
        release_from = property['validRelease']['from'].unpack1("C")
        release_to = property['validRelease']['to'].unpack1("C")
        next unless @release.unpack1("C").between?(release_from, release_to)

        node_p_ary <<
          { epc: property["epc"], name: property["propertyName"]["ja"], description: property["descriptions"]["ja"] }
      end
      p_ary.append({ nodeProfile: node_p_ary })
      p_ary.uniq
    end

    # 引数に指定したEPCの16進数コードを指定すると、そのEPCの["propertyName"]["ja"]を返す
    # EPCが存在しない場合はnilを返す
    def get_epc_name(epc)
      raise(InstanceError.new, "releaseバージョンが設定されていません") if @release.nil?

      properties = @super_class_json['elProperties'].concat(@device_json['elProperties'])
      properties.each do |property|
        next unless property['epc'] == "0x#{epc}"

        # releaseバージョンの一致を確認
        release_from = property['validRelease']['from'].unpack1("C")
        release_to = property['validRelease']['to'].unpack1("C")
        next unless @release.unpack1("C").between?(release_from, release_to)

        return property["propertyName"]["ja"]
      end
      nil
    end

    # 引数に指定したedtのnameとstateに合う16進数バイナリをハッシュで取得する。{epc_name: "", edt_state: ""}
    def check_epc_edt_hex(epc_name, edt_state)
      raise(InstanceError.new, "releaseバージョンが設定されていません") if @release.nil?

      hash = {}
      @device_json ||= make_device_json
      properties = @super_class_json['elProperties'].concat(@device_json['elProperties'])
      properties.each do |property|
        next unless property['shortName'] == epc_name

        # releaseバージョンの一致を確認
        release_from = property['validRelease']['from'].unpack1("C")
        release_to = property['validRelease']['to'].unpack1("C")
        next unless @release.unpack1("C").between?(release_from, release_to)

        break if property['data']['type'] != 'state'

        property['data']['enum'].each do |state|
          next unless state['name'] == edt_state

          hash = { epc_name: property['epc'][2, 2], edt_state: state['edt'][2, 2] }
          break
        end
      end
      hash
    end

    private

      # MRA_V1.2.0のjsonファイルから該当するEOJクラスコードのjsonを選択して、rubyハッシュにparse
      def make_device_json
        return if eoj.nil?

        @device_json = if eoj[0, 4] == "0EF0" # ノード検索対策で条件分岐
                         AssetLoader.load_json("mraData/nodeProfile/0x#0EF0.json")
                       else
                         AssetLoader.load_json("mraData/devices/0x#{eoj[0, 4]}.json")
                       end
        @device_json.merge!(@def_json)
        JsonRefs.call(@device_json)
      rescue Errno::ENOENT
        raise ArgumentError, "対応していないEOJクラスコードです: #{eoj[0, 4]}"
      end
  end

  class ETelegram
    attr_reader :telegram, :tid, :seoj, :deoj, :esv, :opc, :epc, :pdc, :edt, :ei

    def initialize(ehd1: nil, ehd2: nil, tid: nil, seoj: nil, deoj: nil, esv: nil, opc: 0, epc: [], pdc: [], edt: [])
      @ehd1 = ehd1 || ["10"].pack('H*') # ECHONET Lite
      @ehd2 = ehd2 || ["81"].pack('H*') # 規定電文形式
      self.tid = tid unless tid.nil? # トランザクションID
      @seoj = seoj # 3B string
      @deoj = deoj # 3B string
      @esv = esv # string
      @opc = opc # integer
      @epc = epc # string array
      @pdc = pdc # integer array
      @edt = edt # string array
      @code_json = AssetLoader.load_json("code.json") # code_jsonファイルを取得してparse
      @sjson = nil # 自インスタンスのjson
      @djson = nil # 送信先インスタンスのjson
    end

    # UDP送信できる形の電文を作成
    def make_telegram(tid: nil)
      raise(TelegramError.new, "送信元オブジェクトが指定されていません") if @seoj.nil?
      raise(TelegramError.new, "宛先オブジェクトが指定されていません") if @deoj.nil?
      raise(TelegramError.new, "ECHONET Liteサービスが指定されていません") if @esv.nil?
      raise(TelegramError.new, "処理プロパティ数が指定されていません") if @opc.zero?

      (1..@opc).each do |n|
        raise(TelegramError.new, "#{n}番目のECHONET Liteプロパティが指定されていません") if @epc[n - 1].nil?
        raise(TelegramError.new, "#{n}番目のプロパティ値データのバイト数が指定されていません") if @pdc[n - 1].nil?

        unless @pdc[n - 1].zero? || ([@edt[n - 1]].pack('H*').bytesize == @pdc[n - 1])
          raise(TelegramError.new, "#{n}番目のプロパティ値データサイズがPDCと一致しません")
        end
      end

      self.tid = tid || Random.rand(0..0xFFFF) if @tid.nil?
      @telegram = @ehd1 + @ehd2 + [@tid].pack("S>") + [@seoj].pack('H*') +
                  [@deoj].pack('H*') + [@esv].pack('H*') + [@opc].pack('C')
      (1..@opc).each do |n|
        @telegram += [@epc[n - 1]].pack('H*') + [@pdc[n - 1]].pack('C') + [@edt[n - 1]].pack('H*') # UDP通信の電文
      end
      @telegram
    end

    # 電文の中身を見やすい形でハッシュとして返す
    def data(release)
      h1 = @ehd1 == ["10"].pack('H*') ? "ECHONET Lite規格" : "正しく設定されていません"
      h2 = @ehd2 == ["81"].pack('H*') ? "規定電文形式" : "正しく設定されていません"
      tid = @tid || "未定（電文作成時に設定されます）"
      esv = @esv ? @code_json["esv"]["0x#{@esv}"] : "設定されていません"
      epcs = []
      pdcs = []
      edts = []
      sjson
      djson
      @pdc.each_with_index { |pdc, i| pdcs << "#{i + 1}=>#{pdc}B" } unless @pdc.empty?
      unless edt_hash(release).empty?
        edt_hash(release).each_with_index do |(epc, edt), i|
          @ei.epc_list.each do |hash|
            if hash[:epc] == "0x#{epc}"
              epcs << "#{i + 1}=>#{hash[:name]}"
              break
            end
          end
          edts << "#{i + 1}=>#{edt}"
        end
      end

      epcs = epcs.join("　")
      pdcs = pdcs.join("　")
      edts = edts.join("　")

      { 'ヘッダー１' => h1,
        'ヘッダー２' => h2,
        'トランザクションＩＤ' => tid,
        '送信元オブジェクト' => { 'オブジェクト' => @sjson['className']['ja'], 'インスタンスID' => @seoj[4, 2].to_i(16) },
        '宛先オブジェクト' => { 'オブジェクト' => @djson['className']['ja'], 'インスタンスID' => @deoj[4, 2].to_i(16) },
        'ECHONET Liteサービス' => esv,
        '処理プロパティ数' => @opc,
        'ECHONET Liteプロパティ' => epcs,
        'データのバイト数' => pdcs,
        'データ' => edts }
    end

    # 電文の中身を見やすい形で標準出力する
    def print_data(release)
      data_hash = data(release)
      data = <<~DATA
        ヘッダー１：#{data_hash['ヘッダー１']}
        ヘッダー２：#{data_hash['ヘッダー２']}
        トランザクションＩＤ：#{data_hash['トランザクションＩＤ']}
        送信元オブジェクト：オブジェクト＝#{data_hash['送信元オブジェクト']['オブジェクト']}、インスタンスID＝#{data_hash['送信元オブジェクト']['インスタンスID']}
        宛先オブジェクト：オブジェクト＝#{data_hash['宛先オブジェクト']['オブジェクト']}、インスタンスID＝#{data_hash['宛先オブジェクト']['インスタンスID']}
        ECHONET Liteサービス：#{data_hash['ECHONET Liteサービス']}
        処理プロパティ数：#{data_hash['処理プロパティ数']}
        ECHONET Liteプロパティ：#{data_hash['ECHONET Liteプロパティ']}
        データのバイト数：#{data_hash['データのバイト数']}
        データ：#{data_hash['データ']}
      DATA
      print data
    end

    # {epc => show_edt}の形のハッシュを作成
    def edt_hash(release)
      release ||= 'A' if @epc == ['82']
      raise(InstanceError.new, "releaseバージョンが設定されていません") if release.nil?

      raise(TelegramError.new, "seojが未登録です") if @seoj.nil?
      raise(TelegramError.new, "deojが未登録です") if @deoj.nil?
      raise(TelegramError.new, "epcが未登録です") if @epc.empty?

      hash = {}
      @ei ||= make_e_instance(release)
      properties = @ei.super_class_json['elProperties'].concat(@ei.device_json['elProperties'])
      @epc.each_with_index do |epc, i|
        properties.each do |property|
          # Echonetプロパティ（epc）の一致を確認
          next unless property['epc'] == "0x#{epc}"

          # releaseバージョンの一致を確認
          release_from = property['validRelease']['from'].unpack1("C")
          release_to = property['validRelease']['to'].unpack1("C")
          next unless release.unpack1("C").between?(release_from, release_to)

          hash[epc] = show_edt(property, @edt[i])
          break
        end
      end
      hash
    end

    # 以下はsetter

    def tid=(msg)
      raise(TelegramError.new, "引数は整数にしてください") unless msg.is_a? Integer
      raise(TelegramError.new, "引数は0から65535までの数字にしてください") unless msg.between?(0, 65_535)

      @tid = msg
    end

    def seoj=(msg)
      raise(TelegramError.new, "seojは登録済みです。seoj=#{@seoj}") unless @seoj.nil?
      raise(TelegramError.new, "引数は文字列にしてください") unless msg.is_a? String
      raise(TelegramError.new, "引数は6桁の16進数の文字列にする必要があります") unless /^\h{6}$/.match? msg

      @seoj = msg
    end

    def deoj=(msg)
      raise(TelegramError.new, "deojは登録済みです。deoj=#{@deoj}") unless @deoj.nil?
      raise(TelegramError.new, "引数は文字列にしてください") unless msg.is_a? String
      raise(TelegramError.new, "引数は6桁の16進数の文字列にする必要があります") unless /^\h{6}$/.match? msg

      @deoj = msg
    end

    def esv=(msg)
      raise(TelegramError.new, "引数は文字列にしてください") unless msg.is_a? String
      raise(TelegramError.new, "引数は2桁の16進数の文字列にする必要があります") unless /^\h{2}$/.match? msg

      @esv = msg
    end

    def opc=(msg)
      raise(TelegramError.new, "引数は整数にしてください") unless msg.is_a? Integer
      raise(TelegramError.new, "引数は255までの数字にしてください") unless msg.between?(0, 255)

      @opc = msg
    end

    def epc=(msg)
      raise(TelegramError.new, "引数は配列にしてください") unless msg.is_a? Array

      msg.each do |s|
        raise(TelegramError.new, "引数は文字列の配列にしてください") unless s.is_a? String
        raise(TelegramError.new, "配列要素は2桁の16進数の文字列にする必要があります") unless /^\h{2}$/.match? s
      end

      @epc = msg
    end

    def pdc=(msg)
      raise(TelegramError.new, "引数は配列にしてください") unless msg.is_a? Array

      msg.each do |s|
        raise(TelegramError.new, "引数は文字列の配列にしてください") unless s.is_a? Integer
        raise(TelegramError.new, "引数は255までの数字にしてください") unless s.between?(0, 255)
      end

      @pdc = msg
    end

    def edt=(msg)
      raise(TelegramError.new, "引数は配列にしてください") unless msg.is_a? Array

      msg.each do |s|
        raise(TelegramError.new, "引数は文字列の配列にしてください") unless s.is_a? String
        raise(TelegramError.new, "配列要素は2桁の16進数の文字列にする必要があります") unless /^(\h{2})+$/.match? s
      end

      @edt = msg
    end

    private

      # MRA_V1.2.0のjsonファイルから自インスタンスのものを選択して、rubyハッシュにparse
      def sjson
        return unless @sjson.nil?
        return if @seoj.nil?

        @sjson = if @seoj[0, 4] == "0EF0" # ノード検索対策で条件分岐
                   AssetLoader.load_json("mraData/nodeProfile/0x#0EF0.json")
                 else
                   AssetLoader.load_json("mraData/devices/0x#{@seoj[0, 4]}.json")
                 end
        defjson = AssetLoader.load_json("mraData/definitions/definitions.json")
        @sjson.merge!(defjson)
        JsonRefs.call(@sjson)
      end

      # MRA_V1.2.0のjsonファイルから送信先インスタンスのものを選択して、rubyハッシュにparse
      def djson
        return unless @djson.nil?
        return if @deoj.nil?

        @djson = if @deoj[0, 4] == "0EF0" # ノード検索対策で条件分岐
                   AssetLoader.load_json("mraData/nodeProfile/0x#0EF0.json")
                 else
                   AssetLoader.load_json("mraData/devices/0x#{@deoj[0, 4]}.json")
                 end
        defjson = AssetLoader.load_json("mraData/definitions/definitions.json")
        @djson.merge!(defjson)
        JsonRefs.call(@djson)
      end

      # edtの値をわかりやすい形に変換して出力。propertyは@djson['elProperties']でepcと一致したもの。
      def show_edt(property, edt)
        return "ー" if edt.nil?

        data_ary = if property['data']['oneOf'].nil?
                     [property['data']]
                   else
                     property['data']['oneOf']
                   end

        data_ary.each do |data|
          case data['type']
          when "number"
            min = data['minimum']
            max = data['maximum']
            enum = data['enum']
            if enum.nil?
              return edt.to_i(16) if edt.to_i(16).between?(min, max)
            elsif enum.include? edt.to_i(16)
              return edt.to_i(16)
            end

            "'#{edt.to_i(16)}'は設定範囲から外れています"
          when "state"
            data['enum'].each_with_index do |d, j|
              return d['descriptions']['ja'] if d['edt'] == "0x#{edt}"
              return "'#{edt}'に該当する状態はありません" if j == data['enum'].length - 1
            end
          when "level"
            base = data['base']
            max = data['maximum']
            level = edt.to_i(16) - base.to_i(16)
            return level if level.between?(0, max) # >= 0 && level <= max

            "'#{level}'は設定範囲から外れています"
          when "raw"
            min = data['minSize']
            max = data['maxSize']
            return edt if [edt].pack('H*').bytesize.between?(min, max)

            "edtのバイト数が範囲から外れています"
          when "time"
            h = edt[0, 2]
            m = edt[2, 2]
            return "#{h.to_i(16)}時#{m.to_i(16)}分"
          when "date-time"
            y = edt[0, 4]
            mo = edt[4, 2]
            d = edt[6, 2]
            h = edt[8, 2]
            m = edt[10, 2]
            return "#{y.to_i(16)}年#{mo.to_i(16)}月#{d.to_i(16)}日#{h.to_i(16)}時#{m.to_i(16)}分"
          when "object"
            pointa = 0
            res = ""
            data["properties"].each do |data_property|
              case data_property['element']['type']
              when 'number'
                min = data_property['element']['minimum']
                max = data_property['element']['maximum']
                enum = data_property['element']['enum']
                e_name = data_property['elementName']['ja']
                dt = edt[pointa, max.to_s(16).size]
                pointa += max.to_s(16).size
                res << if (enum.nil? && dt.to_i(16).between?(min, max)) || (enum && enum.include?(dt.to_i(16)))
                         "[#{e_name}:#{dt.to_i(16)}]"
                       else
                         "[#{e_name}:'#{dt.to_i(16)}'は設定範囲から外れています]"
                       end
              else
                res << "オプジェクトタイプ\n"
              end
            end

            return res
          when "array"
            return "Arrayタイプ"
          end
        end
      end

      # 電文のepcの主体となるインスタンスをip: nilで作成
      def make_e_instance(release)
        release = 'A' if @epc == ['82']
        raise(InstanceError.new, "releaseバージョンが設定されていません") if release.nil?

        if /6./.match?(@esv)
          clg = @deoj[0, 2]
          cls = @deoj[2, 2]
          itc = @deoj[4, 2]
        elsif /7./.match?(@esv) || /5./.match?(@esv)
          clg = @seoj[0, 2]
          cls = @seoj[2, 2]
          itc = @seoj[4, 2]
        end
        ei = EInstance.new(ip: nil, clg:, cls:, itc:)
        ei.release = release
        ei
      end
  end

  class InstanceError < StandardError
    def initialize(exp = nil)
      super("インスタンスエラー:#{exp}")
    end
  end

  class TelegramError < StandardError
    def initialize(exp = nil)
      super("電文不備:#{exp}")
    end
  end
end
