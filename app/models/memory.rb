module DevMemory
  module Models
    Memory = Struct.new(
      :id,
      :content,
      :summary,
      :memory_type,
      :scope,
      :project_id,
      :source,
      :confidence,
      :tags,
      :created_at,
      keyword_init: true
    )
  end
end
