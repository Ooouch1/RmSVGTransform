require 'matrix'
require_relative 'matrix_ext'
require_relative 'object_ext'
require_relative 'pathdata'

require 'rexml/document'
require 'logger'

class TransformSetting
	@@IGNORABLES = ['svg', 'g', 'clipPath', 'defs', 'marker'].freeze
	@@SKIPPABLES = ['metadata'].freeze
	class << self
		def transform_ignorable_element_names
			@@IGNORABLES
		end
		
		def non_svg_element_names
			@@SKIPPABLES
		end
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

module FloatUtil
	class << self
		@@EPS = 1e-6

		def abs_eq(a, b, eps = @@EPS)
			(a-b).abs < eps
		end

		def relatively_eq(a, b, eps = @@EPS)
			abs_eq(a, b, eps)/Math.max(a.abs, b.abs)
		end
	end
end

class TransformValueParser < HasLogger

	def parse(transform_value_text)
		self.scan(transform_value_text).map { |child_trans|
			kv = self.match_data_to_key_value(child_trans)
			if kv.include?(nil)
				raise ArgumentError, transform_value_text +
					" parse result is: #{kv.to_s}"
			end
			kv
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
		y = values[1].zero_if_nil
		self._create_matrix [1, 0, 0, 1, x, y]
	end

	def _create_scale(values)
		x = values[0]
		y = values[1].proxy_if_nil(x)
		self._create_matrix [values[0], 0, 0, values[1], 0, 0]
	end

	def _create_rotate(values)
		cos_v = Math.cos values[0]
		sin_v = Math.sin values[0]
		x = values[1].zero_if_nil
		y = values[2].zero_if_nil

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

		elem_name = svg_element.name
		

		begin
			applyer = @applyer_factory.create elem_name
			@logger.debug('create applyer: ') {applyer}
		rescue UnacceptableSVGTagError => e
			@logger.warn e if ! TransformSetting.transform_ignorable_element_names.include?(elem_name)
			return []
		end

		#TODO filter non-applicable 'matrix' transform from given items
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
		if parse_result_items.nil? || parse_result_items.empty?
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
			raise UnacceptableSVGTagError.new(
				"<#{svg_tag}> is not acceptable.")
		end
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
		if parse_result.nil? || parse_result.empty?
			return Matrix.I(3)
		end
		(parse_result.map { |key_values|
			@_matrix_factory.create(key_values)
		}).reduce(:*)
	end

	def float_attr(elem, name, value_if_not_exist = nil)
		a = elem.attribute(name)
		return value_if_not_exist if a.nil?
		a.value().to_f()
	end

	def transform_point(
		elem, x_attr_name, y_attr_name, matrix, x_proxy = 0, y_proxy = 0)
		v = matrix.affine(Vector[
			float_attr(elem, x_attr_name, x_proxy),
			float_attr(elem, y_attr_name, y_proxy)
		])
		elem.add_attribute x_attr_name, v[0]
		elem.add_attribute y_attr_name, v[1]
		v
	end

	def _compute_diff(elem, attr_name, dim, matrix)
		diff = float_attr(elem, attr_name)
		return nil if diff.nil?
		matrix.affine_diff(diff, dim)

	end

	def _compute_length(elem, attr_name, dim, matrix)
		diff = _compute_diff(elem, attr_name, dim, matrix)
		return nil if diff.nil?
		diff.abs
	end

	def compute_x_length(elem, attr_name, matrix)
		length = _compute_length(elem, attr_name, 0, matrix)
	end
	def compute_y_length(elem, attr_name, matrix)
		length = _compute_length(elem, attr_name, 1, matrix)
	end

	def compute_x_diff(elem, attr_name, matrix)
		_compute_diff(elem, attr_name, 0, matrix)
	end
	def compute_y_diff(elem, attr_name, matrix)
		_compute_diff(elem, attr_name, 1, matrix)
	end

	def transform_x_diff(elem, attr_name, matrix, proxy_value = nil)
		diff = compute_x_diff(elem, attr_name, matrix)
		elem.add_attribute attr_name, diff.proxy_if_nil(proxy_value)
		diff
	end
	def transform_y_diff(elem, attr_name, matrix, proxy_value = nil)
		diff = compute_y_diff(elem, attr_name, matrix)
		elem.add_attribute attr_name, diff.proxy_if_nil(proxy_value)
		diff
	end

	def transform_x_length(elem, attr_name, matrix, proxy_value = nil)
		length = compute_x_diff(elem, attr_name, matrix)
		length = length.abs if ! length.nil?
		elem.add_attribute attr_name, length.proxy_if_nil(proxy_value)
		length
	end
	def transform_y_length(elem, attr_name, matrix, proxy_value = nil)
		length = compute_y_diff(elem, attr_name, matrix).abs
		length = length.abs if ! length.nil?
		elem.add_attribute attr_name, length.proxy_if_nil(proxy_value)
		length
	end

	def transform_diff_xy(
		elem, x_attr_name, y_attr_name, matrix , x_proxy = 0, y_proxy = 0)
		diffs = matrix.affine_point_diff( Vector[
			float_attr(elem, x_attr_name, x_proxy),
			float_attr(elem, y_attr_name, y_proxy)
		])
		elem.add_attribute x_attr_name, diffs[0]
		elem.add_attribute y_attr_name, diffs[1]
		diffs
	end


end

class TransformApplyerBase
	attr_accessor :helper
	attr_reader :_can_apply
	private :_can_apply
	
	def initialize()
		@_can_apply = {
			'matrix'   => true,
			'translate'=> true,
			'scale'    => true,
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

	def disable_rotate
		@_can_apply['rotate'] = false
	end

	def can_apply(transform_name)
		@_can_apply[transform_name]

	end

=begin
	def can_apply_matrix(matrix)
		if @_can_apply['skewY'] && @_can_apply['skewX'] &&
			@_can_apply['rotate']
			return true
		else
			FloatUtil.abs_eq(matrix[1,0], 0) && FloatUtil.abs_eq(matrix[0,1], 0)
		end
	end
=end

	def apply(svg_element, parse_result)
		_apply svg_element, @helper.matrix_of(parse_result)
	end

	def _apply(svg_element, matrix)
		raise 'Not implemented! '+
			'This method should transform svg_element attributes'
	end


end

class ShapeTransformApplyerBase < TransformApplyerBase
	def initialize()
		super()
		disable_skew
		disable_rotate
	end

	def _transform_x_y(svg_element, matrix)
		return @helper.transform_point(
			svg_element, 'x', 'y', matrix)
	end

	def _transform_cx_cy(svg_element, matrix)
		return @helper.transform_point(
			svg_element, 'cx', 'cy', matrix)
	end

	def _transform_dx_dy(svg_element, matrix)
		return @helper.transform_diff_xy(svg_element, 'dx', 'dy', matrix)
	end

	def _transform_rx_ry(svg_element, matrix)
		rx = @helper.compute_x_length(svg_element,
			'rx', matrix)
		ry = @helper.compute_y_length(svg_element,
			'ry', matrix)
		if rx.nil? 
			if ry.nil?
				rx = 0
				ry = 0
			else
				rx = ry
			end
		elsif ry.nil?
			ry = rx
		end
		svg_element.add_attribute 'rx', rx
		svg_element.add_attribute 'ry', ry
		return [rx, ry]
	end

	def _transform_r(svg_element, matrix)
		return @helper.transform_x_length(svg_element, 'r', matrix)
	end

	def _transform_width_height(svg_element, matrix)
		width = @helper.compute_x_diff(svg_element, 'width', matrix)
		height = @helper.compute_y_diff(svg_element, 'height', matrix)

		if width.nil? || height.nil?
			return nil
		elsif width > 0 && height > 0
			@helper.transform_x_diff svg_element,
				'width', matrix
			@helper.transform_y_diff svg_element,
				'height', matrix
		end
		return [width, height]
	end

	def _transform_rect_area(
		svg_element, matrix, x_name:'x', y_name:'y', w_name:'width', h_name:'height')

		xy = @helper.transform_point(
			svg_element, x_name, y_name, matrix)
		
		wh = _transform_width_height(svg_element, matrix)
		if wh.nil? then return [xy, nil] end
		
		w = wh[0]
		h = wh[1]
		if w < 0
			svg_element.add_attribute 'x', xy[0] + w
			svg_element.add_attribute w_name, -w
		end
		if h < 0
			svg_element.add_attribute 'y', xy[1] + h
			svg_element.add_attribute h_name, -h
		end
		[xy, wh]
	end

end

class TransformApplyer_circle < ShapeTransformApplyerBase
	def _apply(svg_element, matrix)
		_transform_cx_cy svg_element, matrix
		_transform_r svg_element, matrix	
	end
end

class TransformApplyer_ellipse < ShapeTransformApplyerBase
	def _apply(svg_element, matrix)
		_transform_cx_cy svg_element, matrix
		_transform_rx_ry svg_element, matrix
	end
end

class TransformApplyer_path < TransformApplyerBase
	attr_accessor :codec

	def initialize
		super
		@codec = PathData::Codec.new
	end

	def _apply(svg_element, matrix)
		instructions = @codec.decode_path_data(
			svg_element.attribute('d').value)

		begin
			instructions.each do |inst|
				inst.apply! matrix
			end
		rescue => e
			raise ArgumentError, 
				"cannot transform instructions #{instructions.to_s} " +
				"by matrix #{matrix.to_s}\n"+"original error: " + e.message
		end

		svg_element.add_attribute 'd', @codec.encode_path_data(instructions)

	end
end

class TransformApplyer_rect < ShapeTransformApplyerBase
	def _apply(svg_element, matrix)
		_transform_rect_area(svg_element, matrix)
		_transform_rx_ry svg_element, matrix
	end
end
class TransformApplyer_mask < ShapeTransformApplyerBase
	def _apply(svg_element, matrix)
		if svg_element.attribute('maskUnits').nil?
			_transform_rect_area(svg_element, matrix)
		end
	end
end


class TransformApplyer_text < ShapeTransformApplyerBase
	def _apply(svg_element, matrix)
		_transform_x_y svg_element, matrix

		_transform_dx_dy svg_element, matrix
	end
end

class TransformApplyer_tspan < TransformApplyer_text
end

class SVGTransformRemover < HasLogger
	def initialize(log_dest = STDOUT)
		super(log_dest)
		
		@transformer = Transformer.new
		@parser = TransformValueParser.new
	
		@transformer.logger = @logger
		@parser.logger = @logger
	
	end

	def apply(svg_elem, parent_trans_parse_result = [])
		trans_attr = svg_elem.attribute('transform')
		if trans_attr.nil?
			trans_parse_result = parent_trans_parse_result
		else
			trans_parse_result = parent_trans_parse_result +
				@parser.parse(trans_attr.value)
		end

		if TransformSetting.non_svg_element_names.include?(svg_elem.name)
			@logger.info 'skip transforming ' + svg_elem.name + 
				' and its children.'
			return
		end
			
		_do_transform svg_elem, trans_parse_result
	
		svg_elem.elements.each do |child|
			apply child, trans_parse_result
		end

	end

	# private
	def _do_transform(elem, trans_parse_result)
	
		begin
			skipped = @transformer.apply_transforms(elem, trans_parse_result)
			@transformer.set_transform_attribute elem, skipped
		rescue => e
			@transformer.logger.error e
			raise e
		end
	end
end

