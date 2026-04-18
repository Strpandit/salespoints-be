class ApplicationSerializer
  class << self
    attr_accessor :_attributes, :_associations

    def inherited(subclass)
      subclass._attributes = (_attributes || []).dup
      subclass._associations = (_associations || {}).dup
      super
    end

    def attributes(*names)
      self._attributes ||= []
      self._attributes += names.map(&:to_sym)
      self._attributes.uniq!
    end

    def has_many(name, serializer: nil)
      register_association(:has_many, name, serializer)
    end

    def has_one(name, serializer: nil)
      register_association(:has_one, name, serializer)
    end

    def belongs_to(name, serializer: nil)
      register_association(:belongs_to, name, serializer)
    end

    def register_association(kind, name, serializer)
      self._associations ||= {}
      _associations[name.to_sym] = { kind: kind, serializer: serializer }
    end

    def render(resource, options = {})
      new(resource, options).serializable_hash
    end
  end

  attr_reader :resource, :options, :object

  def initialize(resource, options = {})
    @resource = resource
    @options = options || {}
    @object = nil
  end

  def serializable_hash
    if collection?(resource)
      resource.map { |record| serialize_record(record) }
    else
      serialize_record(resource)
    end
  end

  private

  def collection?(value)
    value.respond_to?(:to_ary) && !value.is_a?(Hash)
  end

  def serialize_record(record)
    return nil if record.nil?

    @object = record
    payload = { id: normalize_id(record.id) }

    Array(self.class._attributes).each do |name|
      payload[name] = read_attribute(name)
    end

    selected_associations.each do |name, config|
      value = record.public_send(name)
      serializer_class = resolve_serializer(name, config[:serializer])
      nested_includes = nested_includes_for(name)

      payload[name] =
        if serializer_class
          serializer_class.render(value, options.merge(include: nested_includes))
        elsif config[:kind] == :has_many
          Array(value).map { |item| fallback_serialize(item) }
        else
          fallback_serialize(value)
        end
    end

    payload
  ensure
    @object = nil
  end

  def read_attribute(name)
    if respond_to?(name)
      public_send(name)
    else
      object.public_send(name)
    end
  end

  def selected_associations
    associations = self.class._associations || {}
    requested = Array(options[:include]).map { |entry| entry.to_s.split(".").first.to_sym }.uniq
    return associations if requested.empty?

    associations.slice(*requested)
  end

  def nested_includes_for(name)
    Array(options[:include]).filter_map do |entry|
      parts = entry.to_s.split(".")
      next unless parts.first == name.to_s
      next if parts.length == 1

      parts.drop(1).join(".").to_sym
    end
  end

  def resolve_serializer(name, serializer)
    return serializer if serializer

    "#{name.to_s.classify}Serializer".safe_constantize
  end

  def fallback_serialize(value)
    return nil if value.nil?
    return value.map { |item| fallback_serialize(item) } if value.respond_to?(:to_ary) && !value.is_a?(Hash)
    return value.as_json if value.is_a?(Hash)

    if value.respond_to?(:attributes)
      value.attributes.transform_keys(&:to_sym).merge(id: normalize_id(value.id))
    else
      value
    end
  end

  def normalize_id(value)
    value.is_a?(String) && value.match?(/\A\d+\z/) ? value.to_i : value
  end
end
