module DevMemory
  module Models
    Decision = Struct.new(
      :id,
      :project_id,
      :title,
      :decision,
      :rationale,
      :created_at,
      keyword_init: true
    )
  end
end
