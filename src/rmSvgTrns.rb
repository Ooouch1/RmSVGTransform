require 'matrix'
require 'rexml/document'
require 'logger'

class Obj 
	class << self
		def exists?(obj)
			!(obj.nil? || (defined? obj).nil?)
		end
	end
end

def proxy_if_nil(val, proxy)
	if val.nil? then proxy else val end
end

def zero_if_nil(val)
	proxy_if_nil(val, 0)
end


class Matrix
	def Matrix.affine_columns(cols)
		affine_cols = cols.map {|col| col + [0]}
		affine_cols[cols.length-1][cols[0].length] = 1
		Matrix.columns affine_cols
	end

	def affine(vector)
		if vector.count != column_count - 1
			raise ArgumentError, 'size mismatch'
		end
		computed = self * Vector.elements(vector.to_a() + [1], false)
		Vector.elements [computed[0], computed[1]]
	end
end

class HasLogger
	attr_accessor :logger
	def initialize(dest = STDOUT)
		@logger = Logger.new(dest)
		@logger.level = Logger::WARN
	end

	def log_level=(level)
		@logger.level = level
	end
end

class TransformValueParser < HasLogger

	def parse(transform_value_text)
		self.scan(transform_value_text).map { |child_trans|
			self.match_data_to_key_value(child_trans)
		}
	end

	# private

	def scan(transform_value_text)
		scanned = transform_value_text.scan /(\w+)\s*(\([^(^)]+\))/
		logger.debug('parser, scan') {scanned}
		scanned
	end

	def match_data_to_key_value(match_data)
		logger.debug match_data
		key = match_data[0]
		values = match_data[1].gsub(/[()]/, '').split /[\s,]+/ # lazy expression...
		values = values.map { |v| v.strip().to_f() }
		return {key: key, values: values}
	end

end


class TransformMatrixFactory

	def create(parse_result_item)
		kv = parse_result_item
		eval "self._create_#{kv[:key]} kv[:values]"
	end

	protected	

	def _create_matrix(values)
		Matrix.affine_columns [
			[values[0], values[1]],
			[values[2], values[3]], 
			[values[4], values[5]]
		]
	end

	def _create_translate(values)
		x = values[0]
		y = zero_if_nil(values[1])
		self._create_matrix [1, 0, 0, 1, x, y]
	end

	def _create_scale(values)
		x = values[0]
		y = proxy_if_nil(values[1], x)
		self._create_matrix [values[0], 0, 0, values[1], 0, 0]
	end

	def _create_rotate(values)
		cos_v = Math.cos values[0]
		sin_v = Math.sin values[0]
		x = zero_if_nil(values[1])
		y = zero_if_nil(values[2])

		rotate = self._create_matrix [cos_v, sin_v, -sin_v, cos_v, 0, 0]
		self._create_translate([x, y]) *
				rotate * self._create_translate([-x, -y])
	end
	
	def _create_skewX(values)
		self._create_matrix [1, 0, Math.tan(values[0]), 1, 0, 0]
	end

	def _create_skewY(values)
		self._create_matrix [1, Math.tan(values[0]), 0, 1, 0, 0]
	end

end

class TransformHelper
	def initialize(matrix_factory = TransformMatrixFactory.new())
		@_matrix_factory = matrix_factory
	end

	# This method generates and delegates a matrix of merged tranform for given
	# parse result of tranform attribute.
	#
	# parse_result:: output of TransformValueParser.parse()
	# return:: generated matrix
	# 
	def matrix_of(parse_result)
		(parse_result.map { |key_values|
			@_matrix_factory.create(key_values)
		}).reduce(:*)
	end

	def float_attr(elem, name)
		elem.attribute(name).value().to_f()
	end

end

class UnacceptableSVGTagError < StandardError
end


# facade
class Transformer < HasLogger
	attr_accessor :applyer_factory
	
	def initialize(log_dest = STDOUT)
		super(log_dest)
		@applyer_factory = TransformApplyerFactory.new
	end
	
	def apply_transforms(svg_element,
		parse_result, should_raise_for_disabled_transform = true)
		
		applyer = @applyer_factory.create svg_element.name

		skipped = parse_result.reject { |key_values|
			applyer.can_apply(key_values[:key])
		}
		if skipped.length > 0
			msg = "disabled transform: #{skipped.to_s}, on #{svg_element.to_s}"
			if should_raise_for_disabled_transform
				raise ArgumentError, msg
			else
				@logger.warn msg
			end
		end

		applyer.apply svg_element, (
			parse_result.select { |key_values|
				applyer.can_apply(key_values[:key])
			})

		skipped

	end

	def set_transform_attribute(svg_element, parse_result_items)
		if parse_result_items.empty?
			svg_element.delete_attribute 'transform'
			return
		end

		transform_text = ''
		parse_result_items.each do |kv|
			v_text  = ''
			kv[:values].each_with_index do |v, i|
				v_text.concat v.to_s
				v_text.concat ',' if i < kv[:values].length-1
			end
			transform_text.concat kv[:key] + '(' + v_text + ') '

		end

		svg_element.add_attribute 'transform', transform_text.strip
	end

		
end


class TransformApplyerFactory
	def create(svg_tag)
		begin
			eval "TransformApplyer_#{svg_tag}.new"
		rescue => e
			raise UnacceptableSVGTagError.new("<#{svg_tag}> is not acceptable.")
		end
	end
end

class TransformApplyerBase
	attr_accessor :helper
	
	def initialize()
		@_can_apply = {
			'matrix'   => true,
			'translate'=> true,
			'rotate'   => true,
			'skewX'    => true,
			'skewY'    => true
		}
		@helper = TransformHelper.new()
	end

	def disable_skew
		@_can_apply['skewX'] = false
		@_can_apply['skewY'] = false
	end

	def can_apply(transform_name)
		@_can_apply[transform_name]
	end

	def apply(svg_element, parse_result)
		raise 'Not implemented! '+
			'This method should transform svg_element attributes'
	end

end

class ShapeTransformApplyerBase < TransformApplyerBase
	def initialize()
		super()
		disable_skew
	end
end

class TransformApplyer_circle < ShapeTransformApplyerBase
	def apply(svg_element, parse_result)
		matrix = @helper.matrix_of parse_result
		
		center = Vector.elements [
			@helper.float_attr(svg_element, 'cx'),
			@helper.float_attr(svg_element, 'cy')
		]
		v = matrix.affine(center)
		svg_element.add_attribute 'cx', v[0]
		svg_element.add_attribute 'cy', v[1]

		p = center + (Vector.elements [
			@helper.float_attr(svg_element, 'r'),
			0
		])
		p = matrix.affine(p)
		svg_element.add_attribute 'r', (p - v).norm
	end
end

class PathDataCodec
	@@REG_NUM_STR = "[+-]?\\d+(\\.\\d+)?"
	def decode_path_data(path_data_text)
		reg = /(((\w)((\s|,)*#{@@REG_NUM_STR})+)|[zZ])/
		instruction_texts = path_data_text.scan(reg).map {|m| m[0]}
		instruction_texts.map {|t| decode_instruction_text(t)}
	end

	def decode_instruction_text(text)
		values = (text.scan /(#{@@REG_NUM_STR})/).map {|m| m[0].to_f}

		value_pairs = values.values_at(
			* values.each_index.select {|i| i.even?}).zip(
			values.values_at(* values.each_index.select {|i| i.odd?}))
		
		{
			instruction: text[0],
			points: value_pairs.map {|pair| Vector.elements pair}
		}
	end

	def encode_path_data(instructions)
		encoded = instructions.reduce('') { |path_data, inst|
			path_data +" #{inst[:instruction]}" +
				inst[:points].reduce('') {|text, point|
					text + " #{point[0]},#{point[1]}"
			}
		}
		encoded.strip
	end

end

class TransformApplyer_path < TransformApplyerBase
	attr_accessor :codec

	def initialize
		@codec = PathDataCodec.new
	end

	def apply(svg_element, parse_result)
		instructions = @codec.decode_path_data(svg_element.attribute('d').value)
		matrix = @helper.matrix_of(parse_result)

		instructions.each do |inst|
			inst[:points].map! do |point|
				matrix.affine point
			end
		end

		@codec.encode_path_data(instructions)

	end
end


class TransformApplyer_ellipse < TransformApplyerBase
	def apply(svg_element, parse_result)
	end
end
	
__END__

class Transformer_rect < TransformerBase
	def apply(matrix)
	end
end


class SVGTransformRemover
	def initialize()
		@_matrix_factory = TransformMatrixFactory.new()
	end

	def apply(svg_elem, parent_trans_parse_result)
		svg_elem.elements.each do |elem|
			trans_attr = elem.attribute 'transform'
			if trans_attr.nil?
				trans_parse_result = parent_trans_parse_result
			else
				trans_parse_result = parent_trans_parse_result + @_parser.parse(trans_attr.value)
			end

			# assume that element doesn't have both child element and value.

			if elem.has_elements? # => should be 'g' tag
				self.apply elem, trans_parse_result
			else
				self._do_transform elem, trans_parse_result
			end
		end

	end

	# private
	def _do_transform(elem, trans_parse_result)
		transformer = Transformer.new
		skipped = transformer.apply_transform(elem, trans_parse_result)
		transformer.set_transform_attribute skipped
	end
end

