module EchonetLiteGem
  class ACController < HEMSController
    include Singleton

    attr_reader :temp

    def initialize
      super
      @target_node_eoj = "0130"
      @temp = {}
      @temp_mutex = Mutex.new
    end

    def check_operation_mode(target_instance, ttl: 1)
      ac_status(target_instance, ttl: ttl)["B0"]
    end

    def check_target_temperature(target_instance, ttl: 1)
      temp = ac_status(target_instance, ttl: ttl)["B3"]
      @temp[target_instance.ip] = temp
      temp
    end

    def check_room_temperature(target_instance, ttl: 1)
      ac_status(target_instance, ttl: ttl)["BB"]
    end

    def check_air_flow_level(target_instance, ttl: 1)
      ac_status(target_instance, ttl: ttl)["A0"]
    end

    def check_automatic_control_air_flow_direction(target_instance, ttl: 1)
      ac_status(target_instance, ttl: ttl)["A1"]
    end

    def check_automatic_swing_air_flow(target_instance, ttl: 1)
      ac_status(target_instance, ttl: ttl)["A3"]
    end

    def check_air_flow_direction_vertical(target_instance, ttl: 1)
      ac_status(target_instance, ttl: ttl)["A4"]
    end

    def check_air_flow_direction_horizontal(target_instance, ttl: 1)
      ac_status(target_instance, ttl: ttl)["A5"]
    end

    def check_location(target_instance, ttl: 1)
      response = ac_status(target_instance, ttl: ttl)
      location_code = (response["81"].to_i(16) & "f8".to_i(16)).to_s(16)
      location_code = location_code.rjust(2, "0")
      @code_json["location"]["0x#{location_code}"]
    end

    def change_target_temperature(target_instance, temp)
      @temp_mutex.synchronize do
        @temp[target_instance.ip] = temp
        data_set(["B3"], [temp.to_s(16).upcase], target_instance)
      end
    end

    def temp_up(target_instance)
      @temp_mutex.synchronize do
        @temp[target_instance.ip] = check_target_temperature(target_instance) unless @temp.key?(target_instance.ip)
        @temp[target_instance.ip] += 1
        temp = @temp[target_instance.ip]
        data_set(["B3"], [temp.to_s(16).upcase], target_instance)
      end
    end

    def temp_down(target_instance)
      @temp_mutex.synchronize do
        @temp[target_instance.ip] = check_target_temperature(target_instance) unless @temp.key?(target_instance.ip)
        @temp[target_instance.ip] -= 1
        temp = @temp[target_instance.ip]
        data_set(["B3"], [temp.to_s(16).upcase], target_instance)
      end
    end

    def change_operation_mode(target_instance, mode_name)
      case mode_name
      when "Cooling"
        mode = "42"
      when "Heating"
        mode = "43"
      when "Dehumidification"
        mode = "44"
      when "Air circulation"
        mode = "45"
      else
        raise ArgumentError, "対応していない運転モードです"
      end
      data_set(["B0"], [mode], target_instance)
    end

    private

      # 指定した EInstance の状態をまとめて取得します。
      # 取得する EPC: B0(運転モード), B3(設定温度), 80(電源状態), A4(風向上下), A5(風向左右),
      # A0(風量), 81(設置場所), BB(室温)
      # 取得結果は cached_data_get でキャッシュされ、同じターゲットに対する連続参照で
      # UDP の再送を避けます。
      def ac_status(target_instance, ttl: 1)
        cached_data_get(%w[B0 B3 80 A4 A5 A0 81 BB], target_instance, ttl: ttl)
      end
  end
end
