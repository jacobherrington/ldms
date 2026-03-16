require_relative "../test_helper"
require_relative "../../app/services/embedding_service"

class FakeEmbeddingServiceUnderTest < DevMemory::Services::EmbeddingService
  def initialize(response:, endpoint: "http://localhost:11434/api/embeddings")
    super(endpoint: endpoint)
    @response = response
  end

  private

  def request_embeddings(_text)
    @response
  end
end

class EmbeddingServiceTest < Minitest::Test
  def test_embed_returns_float_vector
    service = FakeEmbeddingServiceUnderTest.new(response: { "embedding" => [1, 2.5, 3] })
    vector = service.embed("hello")

    assert_equal [1.0, 2.5, 3.0], vector
  end

  def test_embed_raises_on_connection_failure
    service = DevMemory::Services::EmbeddingService.new(endpoint: "http://127.0.0.1:9/api/embeddings")

    error = assert_raises(RuntimeError) { service.send(:request_embeddings, "hello") }
    assert_includes error.message, "Could not connect to Ollama"
  end
end
