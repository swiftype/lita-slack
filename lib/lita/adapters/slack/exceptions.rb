module Lita
  module Adapters
    class Slack < Adapter
      class RateLimitingError < StandardError
        attr_reader :response
        attr_reader :response_data

        def initialize(msg, response, response_data)
          @response = response
          @response_data = response_data
          super(msg)
        end
      end
    end
  end
end
