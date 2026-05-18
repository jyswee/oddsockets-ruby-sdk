# frozen_string_literal: true

require_relative "lib/oddsockets/version"

Gem::Specification.new do |spec|
  spec.name = "oddsockets"
  spec.version = OddSockets::VERSION
  spec.authors = ["OddSockets Team"]
  spec.email = ["support@oddsockets.com"]

  spec.summary = "Official Ruby SDK for OddSockets real-time messaging platform"
  spec.description = <<~DESC
    OddSockets Ruby SDK provides a comprehensive interface for real-time messaging,
    presence tracking, message history, and bulk publishing with full Ruby idioms
    and modern async support using Async gem.
  DESC
  spec.homepage = "https://oddsockets.com"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/tygacloud/oddsockets-ruby-sdk"
  spec.metadata["changelog_uri"] = "https://github.com/tygacloud/oddsockets-ruby-sdk/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://rubydoc.info/gems/oddsockets"
  spec.metadata["bug_tracker_uri"] = "https://github.com/tygacloud/oddsockets-ruby-sdk/issues"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "json", "~> 2.6"
  spec.add_dependency "concurrent-ruby", "~> 1.2"
  spec.add_dependency "websocket-client-simple", "~> 0.8"
  spec.add_dependency "zeitwerk", "~> 2.6"

  # Development dependencies
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "rspec-async", "~> 1.16"
  spec.add_development_dependency "webmock", "~> 3.18"
  spec.add_development_dependency "vcr", "~> 6.2"
  spec.add_development_dependency "rubocop", "~> 1.56"
  spec.add_development_dependency "rubocop-rspec", "~> 2.24"
  spec.add_development_dependency "rubocop-performance", "~> 1.19"
  spec.add_development_dependency "yard", "~> 0.9"
  spec.add_development_dependency "redcarpet", "~> 3.6"
  spec.add_development_dependency "simplecov", "~> 0.22"
  spec.add_development_dependency "benchmark-ips", "~> 2.12"
  spec.add_development_dependency "memory_profiler", "~> 1.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "pry", "~> 0.14"
  spec.add_development_dependency "pry-byebug", "~> 3.10"

  # Metadata
  spec.metadata["rubygems_mfa_required"] = "true"
end
