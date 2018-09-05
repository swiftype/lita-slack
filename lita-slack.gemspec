Gem::Specification.new do |spec|
  spec.name          = "shopify-lita-slack"
  spec.version       = "1.8.4"
  spec.authors       = ["Ryan Brushett", "Ridwan Sharif"]
  spec.description   = %q{Lita adapter for Slack.}
  spec.summary       = %q{Lita adapter for Slack.}
  spec.homepage      = "https://github.com/Shopify/lita-slack"
  spec.license       = "MIT"
  spec.metadata      = { "lita_plugin_type" => "adapter" }

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "eventmachine"
  spec.add_runtime_dependency "faraday"
  spec.add_runtime_dependency "faye-websocket", ">= 0.8.0"
  spec.add_runtime_dependency "lita", ">= 4.7.1"
  spec.add_runtime_dependency "multi_json"

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "pry-byebug"
  spec.add_development_dependency "rack-test"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec", ">= 3.0.0"
  spec.add_development_dependency "simplecov", ">= 0.9.2"
  spec.add_development_dependency "codecov"
end
