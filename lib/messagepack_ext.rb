class Time

  def to_msgpack(packer=nil)
    packer ||= MessagePack::Packer.new
    packer.pack self
  end

end

MessagePack::DefaultFactory.register_type(0x00, Symbol)

MessagePack::DefaultFactory.register_type(0x01, Time,
  packer: ->(t){ t.iso8601.to_msgpack },
  unpacker: ->(d){
    Time.parse(MessagePack.unpack(d.force_encoding("ASCII-8BIT")))
  })
