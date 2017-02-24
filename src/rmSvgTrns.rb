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

class Matrix
	def affine(vector)
		if vector.count != column_count - 1
			throw ArgumentError.new 'size mismatch'
		end
		self * (Vector.elements vector.to_a() + [1], false)
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
		self.scan(transform_value_text).map do |child_trans|
			self.match_data_to_key_value  child_trans
		end
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
	attr_accessor :parser

	def initialize()
		@parser = TransformValueParser.new()
	end
	def create(transform_value_text)
		matrices = @parser.parse(transform_value_text).map do |key_values|
			eval "self._create_#{key_values[:key]} key_values[:values]"
		end
		matrices.reduce :*
	end

	protected	

	def _create_matrix(values)
		Matrix.columns [
			[values[0], values[1], 0],
			[values[2], values[3], 0], 
			[values[4], values[5], 1]
		]
	end

	def _create_translate(values)
		self._create_matrix [1, 0, 0, 1, values[0], values[1]]
	end

	def _create_scale(values)
		self._create_matrix [values[0], 0, 0, values[1], 0, 0]
	end

	def _create_rotate(values)
		cos_v = Math.cos values[0]
		sin_v = Math.sin values[0]
		x = values[1]
		y = values[2]

		rotate = self._create_matrix [cos_v, sin_v, -sin_v, cos_v, 0, 0]
		if Obj.exists?(x) && Obj.exists?(y)
			return  self._create_translate([x, y]) *
				rotate * self._create_translate([-x, -y])
		end
		rotate
	end
	
	def _create_skewX(values)
		self._create_matrix [1, 0, Math.tan(values[0]), 1, 0, 0]
	end

	def _create_skewY(values)
		self._create_matrix [1, Math.tan(values[0]), 0, 1, 0, 0]
	end

end

__END__

class TransformableBase
	def initialize(elem)
		@_elem = elem
	end

class Transformable_path < TransformableBase
	def apply(matrix)
	end
end

class Transformable_circle < TransformableBase
	def apply(matrix)
	end
end

class Transformable_rect < TransformableBase
	def apply(matrix)
	end
end

class Transformable_ellipse < TransformableBase
	def apply(matrix)
	end
end

class Transformable_circle < TransformableBase
	def apply(matrix)
	end
end


class SVGTransformRemover
	def initialize()
		@_matrix_factory = TransformMatrixFactory.new()
	end

	def apply(svg_elem, parent_trans_matrix)
		svg_elem.elements.each do |elem|
			trans_attr = elem.attribute 'transform'
			if trans_attr?
				trans_matrix = parent_trans_matrix * @_matrix_factory.create(
					trans_attr.value)
			else
				trans_matrix = parent_trans_matrix
			end

			# assume that element doesn't have both child element and value.

			if elem.has_elements? # => should be 'g' tag
				self.apply elem, trans_matrix
			else
				self._doTransform elem, trans_matrix
			end
		end

	end

	# private
	def _doTransform(elem, trans_matrix)
		transformable = eval("Transformable_#{elem.name}").new(elem)
		transformable.apply(trans_matrix)
	end
end

