require "json"
require "net/http"
require "uri"

module DevMemory
  module Services
    class EmbeddingService
      class EmbeddingError < StandardError; end
      class ConnectionError < EmbeddingError; end
      class ResponseError < EmbeddingError; end

      DEFAULT_MODEL = ENV.fetch("LDMS_EMBED_MODEL", "nomic-embed-text")
      DEFAULT_URL = ENV.fetch("LDMS_OLLAMA_URL", "http://localhost:11434/api/embeddings")

      def initialize(model: DEFAULT_MODEL, endpoint: DEFAULT_URL)
        @model = model
        @endpoint = URI.parse(endpoint)
      end

      def embed(text)
        response = request_embeddings(text.to_s)
        vector = response["embedding"] || response["embeddings"]&.first
        raise ResponseError, "Embedding response missing vector" unless vector.is_a?(Array)

        vector.map(&:to_f)
      end

      private

      def request_embeddings(text)
        req = Net::HTTP::Post.new(@endpoint)
        req["Content-Type"] = "application/json"
        req.body = JSON.generate({ model: @model, prompt: text })

        http = Net::HTTP.new(@endpoint.host, @endpoint.port)
        http.read_timeout = 20
        http.open_timeout = 5
        http.use_ssl = @endpoint.scheme == "https"
        res = http.request(req)
        raise ResponseError, "Embedding request failed (#{res.code})" unless res.code.to_i.between?(200, 299)

        JSON.parse(res.body)
      rescue Errno::ECONNREFUSED
        raise ConnectionError, "Could not connect to Ollama at #{@endpoint}. Start it with `ollama serve`."
      end
    end
  end
end
