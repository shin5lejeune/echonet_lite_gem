RSpec.describe 'echonet_lite.rb' do
  describe EchonetLiteGem::EInstance do
    before do
      @einstance_without_release = EchonetLiteGem::EInstance.new ip: '192.168.0.13', clg: '02', cls: '6B', itc: '01' # 電気温水器
      @einstance = EchonetLiteGem::EInstance.new ip: '192.168.0.13', clg: '02', cls: '6B', itc: '01' # 電気温水器
      @einstance.release = "I"
    end

    describe 'IPアドアレスとEOJコード情報を保持するECHONET Lineノードを表すオブジェクト' do
      it "インスタンス生成時、引数にip(e.g.'192.168.0.13')が必要。無いとArgumentErrorが発生する" do
        expect { EchonetLiteGem::EInstance.new clg: '02', cls: '6B', itc: '01' }.to raise_error ArgumentError
      end
      it "インスタンス生成時、引数にclg(e.g.'02')が必要。無いとArgumentErrorが発生する" do
        expect { EchonetLiteGem::EInstance.new ip: '192.168.0.13', cls: '6B', itc: '01' }.to raise_error ArgumentError
      end
      it "インスタンス生成時、引数にcls(e.g.'6B')が必要。無いとArgumentErrorが発生する" do
        expect { EchonetLiteGem::EInstance.new ip: '192.168.0.13', clg: '02', itc: '01' }.to raise_error ArgumentError
      end
      it "インスタンス生成時、引数にitc(e.g.'01')が必要。無いとArgumentErrorが発生する" do
        expect { EchonetLiteGem::EInstance.new ip: '192.168.0.13', clg: '02', cls: '6B' }.to raise_error ArgumentError
      end
      it '引数にip, clg, cls, itcを指定するとEInstanceのインスタンスが生成される' do
        expect(EchonetLiteGem::EInstance.new(ip: '192.168.0.13', clg: '02', cls: '6B', itc: '01')).to be_is_a EchonetLiteGem::EInstance
      end

      it '未知のEOJクラスコードを指定するとArgumentErrorが発生する' do
        expect do
          EchonetLiteGem::EInstance.new(ip: '192.168.0.13', clg: 'FF', cls: 'FF', itc: '01')
        end.to raise_error(ArgumentError, '対応していないEOJクラスコードです: FFFF')
      end
    end
    describe 'インスタンス変数@super_class_jsonに、0x0000.jsonから読み込んだJSONデータが格納されている' do
      it 'インスタンス.super_class_json["elProperties"][1]["propertyName"]["ja"]に格納せれているのは"設置場所"である' do
        expect(@einstance.super_class_json["elProperties"][1]["propertyName"]["ja"]).to eq "設置場所"
      end
    end
    describe 'インスタンス変数@device_jsonに、該当するEOJクラスコードのjsonが格納されている' do
      it '電気温水器インスタンス.device_json["className"]["ja"]に格納せれているのは"電気温水器"である' do
        expect(@einstance.device_json["className"]["ja"]).to eq "電気温水器"
      end
    end

    describe '#eoj' do
      it '自分のEOJコード(16進数の6桁の文字列)を返す' do
        expect(@einstance.eoj).to eq '026B01'
      end
    end

    describe '#data' do
      it '自分の情報をハッシュ{"IPアドレス"=>""、"オブジェクト"=>""、"インスタンスID"=>""、"Releaseバージョン"=>""}で返す' do
        data = {
          'IPアドレス' => '192.168.0.13',
          'オブジェクト' => '電気温水器',
          'インスタンスID' => '01',
          'Releaseバージョン' => 'I'
        }
        expect(@einstance.data).to eq data
      end
    end

    describe '#print_data' do
      it '自分の情報(ipアドレス、オブジェクト名、インスタンスID、Releaseバージョン)を標準出力に出力する' do
        data = <<~DATA
          ipアドレス：192.168.0.13
          オブジェクト：電気温水器
          インスタンスID：01
          Releaseバージョン：I
        DATA
        expect { @einstance.print_data }.to output(data).to_stdout
      end
    end

    describe '#epc_list' do
      describe '自分（EOJ）の持つEPC(ECHONETプロパティ)情報を、ハッシュ{:epc=>"", :name=>"", :description=>""}の配列で返す' do
        it '得られた配列の１要素目には:epc,:name,:descriptionキーを持つハッシュが格納されている' do
          properties = @einstance.epc_list
          expect(properties[0]).to include(:epc, :name, :description)
        end
        it '得られる配列の最後はnodeProfileのpropertyである' do
          properties = @einstance.epc_list
          last = properties.length - 1
          expect(properties[last]).to_not include(:epc, :name, :description)
          expect(properties[last]).to include(:nodeProfile)
        end
        it 'releaseプロパティが設定されていないとエラーになる' do
          expect { @einstance_without_release.epc_list }.to raise_error "releaseバージョンが設定されていません"
        end
      end
    end
    describe '#get_epc_name' do
      describe '引数にEPCの16進数コードを指定すると、そのEPCの["propertyName"]["ja"]を返す' do
        it '電気温水器のEInstanceでepcに"C0"を指定すると、"昼間沸き増し許可設定"が返る' do
          expect(@einstance.get_epc_name("C0")).to eq "昼間沸き増し許可設定"
        end
      end
    end
    describe '#check_epc_edt_hex' do
      describe '引数にEPCのshortNameとEDTのnameを指定し、それぞれの16進数コードをハッシュ{epc_name: "**", edt_state: "**"}で返す' do
        it '電気温水器のEInstanceでepc_nameにdaytimeReheatingPermission,edt_stateにfalseを指定すると、{epc_name: "C0", edt_state: "42"}が返る' do
          edt_hex = @einstance.check_epc_edt_hex("daytimeReheatingPermission", "false")
          expect(edt_hex).to eq({ epc_name: "C0", edt_state: "42" })
        end
        it '電気温水器のEInstanceでepc_nameにdaytimeReheatingPermission,edt_stateにtrueを指定すると、{epc_name: "C0", edt_state: "41"}が返る' do
          edt_hex = @einstance.check_epc_edt_hex("daytimeReheatingPermission", "true")
          expect(edt_hex).to eq({ epc_name: "C0", edt_state: "41" })
        end
      end
    end
  end

  describe EchonetLiteGem::ETelegram do
    before do
      @telegram = EchonetLiteGem::ETelegram.new(
        tid: 100, seoj: '05FF01', deoj: '026B01', esv: '62', opc: 1, epc: ['E1'], pdc: [0]
      )
      @res_telegram = EchonetLiteGem::ETelegram.new(
        tid: 100,
        seoj: '026B01',
        deoj: '05FF01',
        esv: '72',
        opc: 2,
        epc: %w[E1 E2],
        pdc: [2, 2],
        edt: %w[0064 0190]
      )
      @res_telegram_remote_control = EchonetLiteGem::ETelegram.new(
        tid: 100,
        seoj: '026B01',
        deoj: '05FF01',
        esv: '72',
        opc: 1,
        epc: %w[93],
        pdc: [1],
        edt: %w[61]
      )
      @res_telegram_protocol = EchonetLiteGem::ETelegram.new(
        tid: 100,
        seoj: '026B01',
        deoj: '05FF01',
        esv: '72',
        opc: 1,
        epc: %w[82],
        pdc: [4],
        edt: %w[00004900]
      )
      @telegram_one_of = EchonetLiteGem::ETelegram.new(
        tid: 100,
        seoj: '013001',
        deoj: '05FF01',
        esv: '72',
        opc: 1,
        epc: %w[B0],
        pdc: [1],
        edt: %w[42]
      )
      @blank_t = EchonetLiteGem::ETelegram.new
    end
    describe 'ECHONET Liteフレーム（UDP電文）の各情報を保持するオブジェクト' do
      it 'プロパティとして、tid, seoj, deoj, esv, opc, epc, pdc, edtを持つ' do
        expect(@blank_t).to respond_to(:tid, :seoj, :deoj, :esv, :opc, :epc, :pdc, :edt)
      end
      it 'telegramプロパティを持つ（make_telegramメソッドで作成された16進数の文字列("\x10\x81...")で表現されたUDP電文）' do
        expect(@blank_t).to respond_to(:telegram)
      end
      it 'eiプロパティを持つ（電文のepcの主体となるインスタンスをip: nilで作成したEInstanceオブジェクト）' do
        expect(@blank_t).to respond_to(:ei)
      end
    end

    describe '#opc=' do
      it '負数を指定するとTelegramErrorが発生する' do
        expect { @blank_t.opc = -1 }.to raise_error '引数は255までの数字にしてください'
      end

      it '256を指定するとTelegramErrorが発生する' do
        expect { @blank_t.opc = 256 }.to raise_error '引数は255までの数字にしてください'
      end
    end

    describe '#pdc=' do
      it '配列要素に負数を指定するとTelegramErrorが発生する' do
        expect { @blank_t.pdc = [-1] }.to raise_error '引数は255までの数字にしてください'
      end

      it '配列要素に256を指定するとTelegramErrorが発生する' do
        expect { @blank_t.pdc = [256] }.to raise_error '引数は255までの数字にしてください'
      end
    end

    describe '#epc=' do
      it '配列以外を指定するとTelegramErrorが発生する' do
        expect { @blank_t.epc = 'E1' }.to raise_error '引数は配列にしてください'
      end

      it '配列要素に文字列以外を指定するとTelegramErrorが発生する' do
        expect { @blank_t.epc = [1] }.to raise_error '引数は文字列の配列にしてください'
      end

      it '配列要素に2桁の16進数以外を指定するとTelegramErrorが発生する' do
        expect { @blank_t.epc = ['E'] }.to raise_error '配列要素は2桁の16進数の文字列にする必要があります'
      end
    end

    describe '#edt=' do
      it '配列以外を指定するとTelegramErrorが発生する' do
        expect { @blank_t.edt = '01' }.to raise_error '引数は配列にしてください'
      end

      it '配列要素に文字列以外を指定するとTelegramErrorが発生する' do
        expect { @blank_t.edt = [1] }.to raise_error '引数は文字列の配列にしてください'
      end

      it '配列要素に偶数桁の16進数以外を指定するとTelegramErrorが発生する' do
        expect { @blank_t.edt = ['123'] }.to raise_error '配列要素は2桁の16進数の文字列にする必要があります'
      end

      it '複数バイトの16進数文字列を受け入れる' do
        @blank_t.edt = ['1234']

        expect(@blank_t.edt).to eq ['1234']
      end
    end

    describe '#seoj=' do
      it '文字列以外を指定するとTelegramErrorが発生する' do
        expect { @blank_t.seoj = 26 }.to raise_error '引数は文字列にしてください'
      end

      it '6桁でない文字列を指定するとTelegramErrorが発生する' do
        expect { @blank_t.seoj = '026B' }.to raise_error '引数は6桁の16進数の文字列にする必要があります'
      end

      it '16進数以外を含む文字列を指定するとTelegramErrorが発生する' do
        expect { @blank_t.seoj = '02GG01' }.to raise_error '引数は6桁の16進数の文字列にする必要があります'
      end

      it '一度設定した後に再設定するとTelegramErrorが発生する' do
        @blank_t.seoj = '026B01'

        expect { @blank_t.seoj = '05FF01' }.to raise_error 'seojは登録済みです。seoj=026B01'
      end
    end

    describe '#deoj=' do
      it '文字列以外を指定するとTelegramErrorが発生する' do
        expect { @blank_t.deoj = 26 }.to raise_error '引数は文字列にしてください'
      end

      it '6桁でない文字列を指定するとTelegramErrorが発生する' do
        expect { @blank_t.deoj = '026B' }.to raise_error '引数は6桁の16進数の文字列にする必要があります'
      end

      it '16進数以外を含む文字列を指定するとTelegramErrorが発生する' do
        expect { @blank_t.deoj = '02GG01' }.to raise_error '引数は6桁の16進数の文字列にする必要があります'
      end

      it '一度設定した後に再設定するとTelegramErrorが発生する' do
        @blank_t.deoj = '026B01'

        expect { @blank_t.deoj = '05FF01' }.to raise_error 'deojは登録済みです。deoj=026B01'
      end
    end

    describe '#esv=' do
      it '文字列以外を指定するとTelegramErrorが発生する' do
        expect { @blank_t.esv = 98 }.to raise_error '引数は文字列にしてください'
      end

      it '2桁でない文字列を指定するとTelegramErrorが発生する' do
        expect { @blank_t.esv = '6' }.to raise_error '引数は2桁の16進数の文字列にする必要があります'
      end

      it '16進数以外を含む文字列を指定するとTelegramErrorが発生する' do
        expect { @blank_t.esv = 'GG' }.to raise_error '引数は2桁の16進数の文字列にする必要があります'
      end

      it '2桁の16進数文字列を受け入れる' do
        @blank_t.esv = '62'

        expect(@blank_t.esv).to eq '62'
      end
    end

    describe '#make_telegram' do
      it 'UDP通信用の電文("\x10\x81\x00d\x05\xFF\x01\x02k\x01b\x01\xE1\x00")を作成する' do
        str = "\x10\x81\x00d\x05\xFF\x01\x02k\x01b\x01\xE1\x00"
        str.force_encoding("ASCII-8BIT")
        expect(@telegram.make_telegram).to eq str
      end

      it '作った電文がtelegramプロパティに保存される' do
        str = "\x10\x81\x00d\x05\xFF\x01\x02k\x01b\x01\xE1\x00"
        str.force_encoding("ASCII-8BIT")
        @telegram.make_telegram
        expect(@telegram.telegram).to eq str
      end
      it 'tidがない場合はランダムで付与してから電文を作成' do
        allow(Random).to receive(:rand).and_return(99)
        incomplete_t = EchonetLiteGem::ETelegram.new(
          seoj: '05FF01', deoj: '026B01', esv: '62', opc: 1, epc: ['E1'], pdc: [0]
        )
        str = "\x10\x81\x00c\x05\xFF\x01\x02k\x01b\x01\xE1\x00"
        str.force_encoding("ASCII-8BIT")
        expect(incomplete_t.make_telegram).to eq str
      end

      it 'seoj(送信元オブジェクト)がない場合はTelegramErrorが発生する' do
        incomplete_t = EchonetLiteGem::ETelegram.new(
          tid: 100, deoj: '026B01', esv: '62', opc: 1, epc: ['E1'], pdc: [0]
        )
        expect { incomplete_t.make_telegram }.to raise_error "送信元オブジェクトが指定されていません"
      end
      it 'deoj(宛先オブジェクト)がない場合はTelegramErrorが発生する' do
        incomplete_t = EchonetLiteGem::ETelegram.new(
          tid: 100, seoj: '05FF01', esv: '62', opc: 1, epc: ['E1'], pdc: [0]
        )
        expect { incomplete_t.make_telegram }.to raise_error "宛先オブジェクトが指定されていません"
      end
      it 'esv(ECHONET Liteサービス)がない場合はTelegramErrorが発生する' do
        incomplete_t = EchonetLiteGem::ETelegram.new(
          tid: 100, seoj: '05FF01', deoj: '026B01', opc: 1, epc: ['E1'], pdc: [0]
        )
        expect { incomplete_t.make_telegram }.to raise_error "ECHONET Liteサービスが指定されていません"
      end
      it 'opc(処理プロパティ数)がない場合はTelegramErrorが発生する' do
        incomplete_t = EchonetLiteGem::ETelegram.new(
          tid: 100, seoj: '05FF01', deoj: '026B01', esv: '62', epc: ['E1'], pdc: [0]
        )
        expect { incomplete_t.make_telegram }.to raise_error "処理プロパティ数が指定されていません"
      end
      it 'epc(ECHONET Liteプロパティ)がない場合はTelegramErrorが発生する' do
        incomplete_t = EchonetLiteGem::ETelegram.new(
          tid: 100, seoj: '05FF01', deoj: '026B01', esv: '62', opc: 1, pdc: [0]
        )
        expect { incomplete_t.make_telegram }.to raise_error "1番目のECHONET Liteプロパティが指定されていません"
      end
      it 'pdc(プロパティ値データのバイト数)がない場合はTelegramErrorが発生する' do
        incomplete_t = EchonetLiteGem::ETelegram.new(
          tid: 100, seoj: '05FF01', deoj: '026B01', esv: '62', opc: 1, epc: ['E1']
        )
        expect { incomplete_t.make_telegram }.to raise_error "1番目のプロパティ値データのバイト数が指定されていません"
      end
      it 'pdc(edtのバイト数）とedt（プロパティ値データ）のバイト数が一致しない場合はTelegramErrorが発生する' do
        incomplete_t = EchonetLiteGem::ETelegram.new(
          tid: 100, seoj: '05FF01', deoj: '026B01', esv: '62', opc: 1, epc: ['E1'], pdc: [1], edt: ['7777']
        )
        expect { incomplete_t.make_telegram }.to raise_error "1番目のプロパティ値データサイズがPDCと一致しません"
      end

      it '複数のプロパティを指定する場合も、epc(ECHONET Liteプロパティ)がない場合はTelegramErrorが発生する' do
        incomplete_t = EchonetLiteGem::ETelegram.new(
          tid: 100, seoj: '05FF01', deoj: '026B01', esv: '62', epc: ['E1'], opc: 2, pdc: [1, 2], edt: %w[77 88]
        )
        expect { incomplete_t.make_telegram }.to raise_error "2番目のECHONET Liteプロパティが指定されていません"
      end
      it '複数のプロパティを指定する場合も、pdc(プロパティ値データのバイト数)がない場合はTelegramErrorが発生する' do
        incomplete_t = EchonetLiteGem::ETelegram.new(
          tid: 100, seoj: '05FF01', deoj: '026B01', esv: '62', opc: 2, epc: %w[E1 E2], pdc: [1], edt: %w[77 88]
        )
        expect { incomplete_t.make_telegram }.to raise_error "2番目のプロパティ値データのバイト数が指定されていません"
      end
      it '複数のプロパティを指定する場合も、pdcとedtのバイト数が一致しない場合はTelegramErrorが発生する' do
        incomplete_t = EchonetLiteGem::ETelegram.new(
          tid: 100, seoj: '05FF01', deoj: '026B01', esv: '62', opc: 2, epc: %w[E1 E2], pdc: [1, 2], edt: %w[77 88]
        )
        expect { incomplete_t.make_telegram }.to raise_error "2番目のプロパティ値データサイズがPDCと一致しません"
      end
    end

    describe '#data' do
      it '送信電文では送信元デバイスのプロパティを使って伝聞データをハッシュで返す' do
        data = {
          'ヘッダー１' => 'ECHONET Lite規格',
          'ヘッダー２' => '規定電文形式',
          'トランザクションＩＤ' => 100,
          '送信元オブジェクト' => { 'オブジェクト' => 'コントローラ', 'インスタンスID' => 1 },
          '宛先オブジェクト' => { 'オブジェクト' => '電気温水器', 'インスタンスID' => 1 },
          'ECHONET Liteサービス' => 'プロパティ値読み出し要求',
          '処理プロパティ数' => 1,
          'ECHONET Liteプロパティ' => '1=>残湯量計測値',
          'データのバイト数' => '1=>0B',
          'データ' => '1=>ー'
        }
        expect(@telegram.data("I")).to eq data
      end

      it '返答電文では送信先デバイスのプロパティを使って伝聞データをハッシュで返す' do
        data = {
          'ヘッダー１' => 'ECHONET Lite規格',
          'ヘッダー２' => '規定電文形式',
          'トランザクションＩＤ' => 100,
          '送信元オブジェクト' => { 'オブジェクト' => '電気温水器', 'インスタンスID' => 1 },
          '宛先オブジェクト' => { 'オブジェクト' => 'コントローラ', 'インスタンスID' => 1 },
          'ECHONET Liteサービス' => 'プロパティ値読み出し応答',
          '処理プロパティ数' => 2,
          'ECHONET Liteプロパティ' => '1=>残湯量計測値　2=>タンク容量値',
          'データのバイト数' => '1=>2B　2=>2B',
          'データ' => '1=>100　2=>400'
        }
        expect(@res_telegram.data("I")).to eq data
      end

      it '引数にreleaseバージョンを指定しないと、"releaseバージョンが設定されていません"とエラーになる' do
        expect { @res_telegram.print_data(nil) }.to raise_error "releaseバージョンが設定されていません"
      end

      it 'releaseバージョンに合った情報を返す' do
        data = {
          'ヘッダー１' => 'ECHONET Lite規格',
          'ヘッダー２' => '規定電文形式',
          'トランザクションＩＤ' => 100,
          '送信元オブジェクト' => { 'オブジェクト' => '電気温水器', 'インスタンスID' => 1 },
          '宛先オブジェクト' => { 'オブジェクト' => 'コントローラ', 'インスタンスID' => 1 },
          'ECHONET Liteサービス' => 'プロパティ値読み出し応答',
          '処理プロパティ数' => 1,
          'ECHONET Liteプロパティ' => '1=>遠隔操作設定',
          'データのバイト数' => '1=>1B',
          'データ' => '1=>通信回線正常(公衆回線経由の操作不可)'
        }
        expect(@res_telegram_remote_control.data("I")).to eq data
      end
    end
    describe '#print_data' do
      it 'dataメソッドを使って得た電文データを標準出力に表示' do
        data_hash = {
          'ヘッダー１' => 'ECHONET Lite規格',
          'ヘッダー２' => '規定電文形式',
          'トランザクションＩＤ' => 100,
          '送信元オブジェクト' => { 'オブジェクト' => 'コントローラ', 'インスタンスID' => 1 },
          '宛先オブジェクト' => { 'オブジェクト' => '電気温水器', 'インスタンスID' => 1 },
          'ECHONET Liteサービス' => 'プロパティ値読み出し要求',
          '処理プロパティ数' => 1,
          'ECHONET Liteプロパティ' => '1=>残湯量計測値',
          'データのバイト数' => '1=>0B',
          'データ' => '1=>ー'
        }

        expect(@telegram).to receive(:data).with('I').once.and_return(data_hash) # dataメソッドの戻り値をモックする

        data = <<~DATA
          ヘッダー１：ECHONET Lite規格
          ヘッダー２：規定電文形式
          トランザクションＩＤ：100
          送信元オブジェクト：オブジェクト＝コントローラ、インスタンスID＝1
          宛先オブジェクト：オブジェクト＝電気温水器、インスタンスID＝1
          ECHONET Liteサービス：プロパティ値読み出し要求
          処理プロパティ数：1
          ECHONET Liteプロパティ：1=>残湯量計測値
          データのバイト数：1=>0B
          データ：1=>ー
        DATA
        expect { @telegram.print_data("I") }.to output(data).to_stdout
      end

      it '引数にreleaseバージョンを指定しないと、"releaseバージョンが設定されていません"とエラーになる' do
        expect { @res_telegram.print_data(nil) }.to raise_error "releaseバージョンが設定されていません"
      end
    end

    describe '#edt_hash' do
      it 'EPC(プロパティコード)をキー、EDT(データ)を値として、ハッシュ{"E1" => 100, "E2" => 400}で出力する' do
        hash = { "E1" => 100, "E2" => 400 }
        expect(@res_telegram.edt_hash("I")).to eq hash
      end

      it 'propertyのdateがoneOfとなっていた場合も対応できる' do
        hash = { 'B0' => '冷房' }
        expect(@telegram_one_of.edt_hash("I")).to eq hash
      end

      it 'オブジェクトタイプの返答データにも対応できる' do
        telegram = EchonetLiteGem::ETelegram.new(
          tid: 100,
          seoj: '026B01',
          deoj: '05FF01',
          esv: '72',
          opc: 1,
          epc: ['CB'],
          pdc: [16],
          edt: %w[000003E8000007D000000BB800000FA0]
        )
        hash = { 'CB' => '[10時:1000][13時:2000][15時:3000][17時:4000]' }

        expect(telegram.edt_hash("I")).to eq hash
      end

      it '引数(EInstanceのreleaseバージョン)がnilだとエラーになる' do
        expect { @res_telegram.edt_hash(nil) }.to raise_error "releaseバージョンが設定されていません"
      end

      it '引数(EInstanceのreleaseバージョン)がnilでも、releaseバージョン問い合わせ時はエラーにならない' do
        hash = { '82' => '00004900' }
        expect(@res_telegram_protocol.edt_hash(nil)).to eq hash
      end
    end

    describe "#tid" do
      it "トランザクションID（TID）を数字で返す" do
        expect(@telegram.tid).to eq 100
      end
    end

    describe '#tid=' do
      it '整数以外を指定するとTelegramErrorが発生する' do
        expect { @blank_t.tid = '100' }.to raise_error '引数は整数にしてください'
      end

      it '整数を指定するとTIDを設定できる' do
        @blank_t.tid = 100

        expect(@blank_t.tid).to eq 100
      end

      it '負数を指定するとTelegramErrorが発生する' do
        expect { @blank_t.tid = -1 }.to raise_error '引数は0から65535までの数字にしてください'
      end

      it '65536を指定するとTelegramErrorが発生する' do
        expect { @blank_t.tid = 65_536 }.to raise_error '引数は0から65535までの数字にしてください'
      end

      it '0xffffを指定すると受け入れ、数値として取得できる' do
        @blank_t.tid = 0xffff

        expect(@blank_t.tid).to eq 0xffff
      end
    end
  end
end
