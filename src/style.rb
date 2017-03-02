
module Style
	class AttributeBase
		attr_accessor :value

		def initialize(key, value)
			@key = key
			@value = value
		end
		def apply!(matrix)
		end

		def encode
			"#{@key}:#{@value};"
		end
	end

	class StrokeWidth < AttributeBase
		def initialize(key, value)
			super(key, value.to_f)
		end

		def apply!(matrix)
			# Remove Inkscape-specific treatment.
			# You can find it in c++ code of it.
			@value *= Math.sqrt(matrix.determinant.abs)
		end
	end

	class StubAttribute < AttributeBase
	end

	class Codec
		def decode(style_text)
			style_text.split(';').map { |kv|
				kv = kv.split(':').map! { |t|
					t.strip
				}
				decode_attribute(kv[0], kv[1])
			}
		end

		def decode_attribute(key, value)
			case key
			when 'stroke-width'
				return StrokeWidth.new(key, value)
			else
				return StubAttribute.new(key, value)
			end
		end

		def encode(style_attributes)
			(style_attributes.map {|a| a.encode}).join('')
		end

	end
end
