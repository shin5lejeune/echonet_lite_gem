# frozen_string_literal: true

require_relative "lib/echonet_lite_gem/version"

Gem::Specification.new do |spec|
  spec.name = "echonet_lite_gem"
  spec.version = EchonetLiteGem::VERSION
  spec.authors = ["shin5lejeune"]
  spec.email = ["shin5lejeune@gmail.com"]

  spec.summary = "Ruby library for ECHONET Lite messaging and device control"
  spec.description = "A Ruby library for generating and parsing ECHONET Lite telegrams, discovering devices, and reading or writing device properties."
  spec.homepage = "https://github.com/shin5lejeune/echonet_lite_gem.git"
  spec.license = "MIT"

  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata['rubygems_mfa_required'] = 'true'
  # spec.metadata["allowed_push_host"] = "TODO: Set to your gem server 'https://example.com'"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.end_with?(".gem") ||
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
