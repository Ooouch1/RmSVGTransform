
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
			val_match = value.match(/[.0-9]+/)

			unit_match = value.match(/[a-z]+/)
			@unit = unit_match ? unit_match[0] : ''

			super(key, val_match[0].to_f)
		end

		def apply!(matrix)
			# Remove Inkscape-specific treatment.
			# You can find it in c++ code of it.
			@value *= Math.sqrt(matrix.determinant.abs)
		end

		def encode
			"#{@key}:#{@value}#{@unit};"
		end
	end

	class StrokeDashArray < AttributeBase
		def initialize(key, value)
			super(key, value.split(',').map{|v| v.strip.to_f})
		end

		def apply!(matrix)
			# Remove Inkscape-specific treatment. Maybe correct.
			@value = @value.map{ |v| v * Math.sqrt(matrix.determinant.abs)}
		end

		def encode
			if @value.size == 1
				return "#{@key}:none;"
			end
			
			"#{@key}:#{@value.join ','};"
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
			when 'stroke-dasharray'
				return StrokeDashArray.new(key, value)
			else
				return StubAttribute.new(key, value)
			end
		end

		def encode(style_attributes)
			(style_attributes.map {|a| a.encode}).join('')
		end

	end
end
