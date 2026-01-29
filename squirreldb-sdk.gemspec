# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "squirreldb-sdk"
  spec.version = "0.1.0"
  spec.authors = ["SquirrelDB Contributors"]
  spec.summary = "Ruby client for SquirrelDB"
  spec.description = "A Ruby client for connecting to SquirrelDB realtime database"
  spec.homepage = ""
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.files = Dir["lib/**/*"]
  spec.require_paths = ["lib"]

  spec.add_dependency "websocket-client-simple", "~> 0.9"
  spec.add_dependency "json", "~> 2.0"

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "minitest", "~> 5.0"
end
