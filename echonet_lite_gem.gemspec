# frozen_string_literal: true

require_relative "lib/echonet_lite_gem/version"

Gem::Specification.new do |spec|
  spec.name = "echonet_lite_gem"
  spec.version = EchonetLiteGem::VERSION
  spec.authors = ["shin5lejeune"]
  spec.email = ["shin5lejeune@gmail.com"]

  spec.summary = "ECHONET Lite support for My HEMS"
  spec.description = "ECHONET Lite telegram parsing and node communication"
  # spec.homepage = "TODO: Put your gem's website or public repo URL here."
  spec.license = "MIT"

  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata['rubygems_mfa_required'] = 'true'
  # spec.metadata["allowed_push_host"] = "TODO: Set to your gem server 'https://example.com'"
  # spec.metadata["homepage_uri"] = spec.homepage
  # spec.metadata["source_code_uri"] = "TODO: Put your gem's public repo URL here."
  # spec.metadata["changelog_uri"] = "TODO: Put your gem's CHANGELOG.md URL here."

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  # spec.bindir = "exe"
  # spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "json_refs", "~> 0.1.8"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
