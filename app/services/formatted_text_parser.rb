class FormattedTextParser
  BULLET_PREFIX = /\A[-*]\s+/.freeze
  NUMBERED_PREFIX = /\A\d+[\.\)]\s+/.freeze

  def self.parse(text)
    new(text).parse
  end

  def initialize(text)
    @text = text.to_s
  end

  def parse
    lines = @text.gsub("\r\n", "\n").split("\n")
    blocks = []
    paragraph_buffer = []

    flush_paragraph = lambda do
      next if paragraph_buffer.empty?

      blocks << {
        type: "paragraph",
        text: paragraph_buffer.join(" ").strip
      }
      paragraph_buffer.clear
    end

    index = 0
    while index < lines.length
      line = lines[index].to_s.rstrip

      if line.strip.blank?
        flush_paragraph.call
        index += 1
        next
      end

      if line.match?(BULLET_PREFIX)
        flush_paragraph.call
        items = []
        while index < lines.length && lines[index].to_s.strip.match?(BULLET_PREFIX)
          items << lines[index].to_s.strip.sub(BULLET_PREFIX, "").strip
          index += 1
        end
        blocks << { type: "bullet_list", items: items }
        next
      end

      if line.match?(NUMBERED_PREFIX)
        flush_paragraph.call
        items = []
        while index < lines.length && lines[index].to_s.strip.match?(NUMBERED_PREFIX)
          items << lines[index].to_s.strip.sub(NUMBERED_PREFIX, "").strip
          index += 1
        end
        blocks << { type: "numbered_list", items: items }
        next
      end

      paragraph_buffer << line.strip
      index += 1
    end

    flush_paragraph.call
    blocks
  end
end
