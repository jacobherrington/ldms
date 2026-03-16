module DevMemory
  module Models
    Session = Struct.new(
      :id,
      :project_id,
      :started_at,
      :ended_at,
      :summary,
      keyword_init: true
    )
  end
end
