module EchonetLiteGem
  module AssetLoader
    module_function

    def load_json(filename)
      path = File.expand_path("data/#{filename}", __dir__)
      JSON.parse(File.read(path))
    end
  end
end
