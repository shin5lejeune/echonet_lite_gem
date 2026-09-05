module EchonetLiteGem
  # EWHは、ElectricWaterHeater(電気温水機）の略。Ecocuteだと、Railsのcontrollerと名前が衝突してしまうので。
  class EWHController < HEMSController
    include Singleton

    def initialize
      super
      @target_node_eoj = "026B"
    end

    # 沸き上げ自動設定の状況を確認する
    def check_automatic_water_heating(ecocute_instance, ttl: 1)
      ewh_status(ecocute_instance, ttl: ttl)["B0"]
    end

    # 沸き上げ中状態の確認
    def check_water_heater_status(ecocute_instance, ttl: 1)
      ewh_status(ecocute_instance, ttl: ttl)["B2"]
    end

    # 手動沸き上げ停止日数設定値の確認
    def check_heating_stop_days(ecocute_instance, ttl: 1)
      ewh_status(ecocute_instance, ttl: ttl)["B4"]
    end

    # 昼間沸き増し許可設定の確認
    def check_daytime_reheating_permission(ecocute_instance, ttl: 1)
      ewh_status(ecocute_instance, ttl: ttl)["C0"]
    end

    # 給湯中状態の確認
    def check_hot_water_supply_status(ecocute_instance, ttl: 1)
      ewh_status(ecocute_instance, ttl: ttl)["C3"]
    end

    # エネルギーシフト参加状態の確認
    def check_energy_shift_participation(ecocute_instance, ttl: 1)
      ewh_status(ecocute_instance, ttl: ttl)["C7"]
    end

    # 沸き上げ開始時刻の確認
    def check_standard_time_to_start_heating(ecocute_instance, ttl: 1)
      ewh_status(ecocute_instance, ttl: ttl)["C8"]
    end

    # エネルギーシフト回数の確認
    def check_number_of_energy_shifts(ecocute_instance, ttl: 1)
      ewh_status(ecocute_instance, ttl: ttl)["C9"]
    end

    # 昼間沸き上げ開始時刻１の確認
    def check_water_heating_shift_time1(ecocute_instance, ttl: 1)
      ewh_status(ecocute_instance, ttl: ttl)["CA"]
    end

    # 昼間沸き上げ開始時刻１での　沸き上げ予測電力量の確認
    def check_estimated_electric_energy_at_shift_time1(ecocute_instance, ttl: 1)
      ewh_status(ecocute_instance, ttl: ttl)["CB"]
    end

    # 時間あたり消費電力量１の確認
    def check_electric_energy_consukption_rate1(ecocute_instance, ttl: 1)
      ewh_status(ecocute_instance, ttl: ttl)["CC"]
    end

    # 給油温度設定値の確認
    def check_target_supplied_water_temperature(ecocute_instance, ttl: 1)
      ewh_status(ecocute_instance, ttl: ttl)["D1"]
    end

    # 風呂温度設定値の確認
    def check_target_bath_water_temperature(ecocute_instance, ttl: 1)
      ewh_status(ecocute_instance, ttl: ttl)["D3"]
    end

    # 現時点の残湯量を確認する。
    def check_water_amount(ecocute_instance, ttl: 1)
      ewh_status(ecocute_instance, ttl: ttl)["E1"]
    end

    # 風呂自動モード設定の確認
    def check_automatic_bath_operation(ecocute_instance, ttl: 1)
      ewh_status(ecocute_instance, ttl: ttl)["E3"]
    end

    # 風呂動作状態監視の確認
    def check_bath_operation_status_monitor(ecocute_instance, ttl: 1)
      ewh_status(ecocute_instance, ttl: ttl)["EA"]
    end

    # 風呂湯量設定３の確認
    def check_bath_water_volume3(ecocute_instance, ttl: 1)
      ewh_status(ecocute_instance, ttl: ttl)["EE"]
    end

    # エコキュートの沸き上げ自動設定を変更する
    # state:自動→"auto”、手動停止→"manualNoHeating"、手動沸き上げ→"manualHeating"
    def change_automatic_water_heating(ecocute_instance, state)
      raise ArgumentError, "対応していない沸き上げ設定です" unless %w[auto manualNoHeating manualHeating].include?(state)

      hex_hash = ecocute_instance.check_epc_edt_hex("automaticWaterHeating", state)
      epc = hex_hash[:epc_name]
      edt = hex_hash[:edt_state]
      data_set([epc], [edt], ecocute_instance)
    end

    private

      # 指定した EInstance のエコキュート状態をまとめて取得します。
      # 取得する EPC: B0(沸き上げ自動設定), B2(沸き上げ中状態), B4(手動停止日数設定),
      # C0(昼間沸き増し許可), D1(給油温度設定), D3(風呂温度設定), E1(残湯量),
      # E3(風呂自動モード設定), EA(風呂動作状態監視), EE(風呂湯量設定3)
      # 取得結果は cached_data_get でキャッシュされ、同じターゲットに対する連続参照で
      # UDP の再送を避けます。
      def ewh_status(ecocute_instance, ttl: 1)
        cached_data_get(%w[B0 B2 B4 C0 D1 D3 E1 E3 EA EE], ecocute_instance, ttl: ttl)
      end
  end
end
