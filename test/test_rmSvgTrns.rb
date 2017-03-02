require_relative '../src/rmSvgTrns'

require 'test/unit'
require 'test/unit/rr' # not a default package
require_relative './testlib'

require 'logger'

$test_logger = Logger.new(STDOUT)

class ParserTest < Test::Unit::TestCase
	def create_parser
		parser = TransformValueParser.new()
		parser.log_level = Logger::DEBUG
		parser
	end

	def test_parse
		parser = create_parser
		key_value_arrays = parser.parse 'matrix(1, 2, 3, 4, 5, 6)'
		$test_logger.info key_value_arrays

		assert_equal 1, key_value_arrays.length

		self.assert_parse_result 'matrix', [1,2,3,4,5,6], key_value_arrays[0]
	end

	def test_parse_multi
		parser = create_parser
		key_value_arrays = parser.parse 'matrix(1, 2, 3, 4, 5, 6) translate (-0.1 +1.1)'

		self.assert_parse_result 'matrix', [1,2,3,4,5,6], key_value_arrays[0]
		self.assert_parse_result 'translate', [-0.1, 1.1], key_value_arrays[1]
	end
		
	def assert_parse_result(expected_key, expected_values, key_values)
		key = key_values[:key]
		values = key_values[:values]
		assert_equal expected_key, key
		assert_array_equal expected_values, values
	end
end

def assert_matrix_element(v, matrix, i, j) 
	assert_equal v, matrix[i, j], "@#{i} , #{j}"
end

class MatrixFactoryTest < Test::Unit::TestCase
	sub_test_case 'single_transform' do
		setup do
			@factory = TransformMatrixFactory.new()
		end

		test 'matrix' do
			matrix = @factory.create({key:'matrix', values:[0,1,2,3,4,5]})
			$test_logger.info('Factory:single_transform, matrix') {matrix}

			assert_matrix_element 0, matrix, 0,0
			assert_matrix_element 1, matrix, 1,0
			assert_matrix_element 0, matrix, 2,0

			assert_matrix_element 2, matrix, 0,1
			assert_matrix_element 3, matrix, 1,1
			assert_matrix_element 0, matrix, 2,1

			assert_matrix_element 4, matrix, 0,2
			assert_matrix_element 5, matrix, 1,2
			assert_matrix_element 1, matrix, 2,2
		end

		test 'rotate: center is origin' do
			
			matrix = @factory.create({key:'rotate', values:[-Math::PI/4]})
			# p = matrix * Vector[1, 0, 1]
			p = matrix.affine Vector[1, 0]
			
			assert_float_eq  Math.sqrt(2)/2, p[0]
			assert_float_eq -Math.sqrt(2)/2, p[1]


		end
		
		test 'rotate: center is indicated' do
			matrix = @factory.create({key:'rotate', values:[-Math::PI/4, 1, 1]})
			$test_logger.info('Factory:single_transform, rotate with center') {matrix}
			p = matrix.affine Vector[1, 0]
			
			assert_float_eq 1 - Math.sqrt(2)/2, p[0], 'test on x'
			assert_float_eq 1 - Math.sqrt(2)/2, p[1], 'test on y'

	
		end
	end
	
end

module DOMTestUtil
	def assert_float_attr(element, expected, name)
		if expected.nil? then assert_nil element.attribute(name)
		else assert_float_eq expected, element.attribute(name).value.to_f
		end
	end
end

class TransformHelperTest < Test::Unit::TestCase
	include DOMTestUtil

	def setup
		@helper = TransformHelper.new
	end

	def test_matrix_of
		parse_result = [
			{key: 'matrix', values: [2, 0, 0, 3, 0, 0]},
			{key: 'translate', values: [1, 4]}
		]
		matrix = @helper.matrix_of(parse_result)
		assert_matrix_element  2, matrix, 0,0
		assert_matrix_element  0, matrix, 1,0
		assert_matrix_element  0, matrix, 0,1
		assert_matrix_element  3, matrix, 1,1
		assert_matrix_element  2, matrix, 0,2
		assert_matrix_element 12, matrix, 1,2

		assert_matrix_element 0, matrix, 2,0
		assert_matrix_element 0, matrix, 2,1
		assert_matrix_element 1, matrix, 2,2
	end

	sub_test_case 'test transform_x_length' do
		def test_usual_case
			element = REXML::Element.new('rect')
			element.add_attribute 'width', 1.2
			w = @helper.transform_x_length(
				element, 'width', Matrix.affine_columns(
					[[2,0], [0,3], [0,0]]
				))
			assert_float_attr element, 2.4, 'width'

		end

		def test_proxy_used
			element = REXML::Element.new('rect')
			w = @helper.transform_x_length(
				element, 'width', Matrix.affine_columns(
					[[2,0], [0,3], [0,0]]
				), 10)
			assert_float_attr element, 10, 'width'
		end

		def test_proxy_is_also_nil
			element = REXML::Element.new('rect')
			w = @helper.transform_x_length(
				element, 'width', Matrix.affine_columns(
					[[2,0], [0,3], [0,0]]
				), nil)
			assert_float_attr element, nil, 'width'
		end
	end
end

class TransformerTest < Test::Unit::TestCase
	class StubTransformApplyer < TransformApplyerBase
		def apply (svg_element, parse_result)
			'stub'
		end
	end

	def test_effect_of_applyers_disable_skew
		transformer = Transformer.new
		applyer = StubTransformApplyer.new
		stub(transformer.applyer_factory).create {applyer}
		element_dummy = REXML::Element.new 'circle'

		assert_nothing_raised do
			transformer.apply_transforms element_dummy, [
				{key: 'translate', values:[1,2]},
				{key: 'skewX', values:[0.5]}
			]
		end	

		applyer.disable_skew

		assert_raise do
			transformer.apply_transforms element_dummy, [
				{key: 'skewX', values:[0.5]}
			], true
		end

		assert_raise do
			transformer.apply_transforms element_dummy, [
				{key: 'skewY', values:[0.5]}
			]
		end

		skipped = transformer.apply_transforms element_dummy, [
			{key: 'translate', values:[1,2]},
			{key: 'skewY', values:[0.5]}
		], false

		assert_equal 1, skipped.length
		assert_equal 'skewY', skipped[0][:key]

	end

	def test_set_transform_attribute
		transformer = Transformer.new
		
		element = REXML::Element.new 'circle'
		element.add_attribute 'transform', 'garbage'
		transformer.set_transform_attribute element, [
			{key: 'translate', values:[1,2]},
			{key: 'skewY', values:[0.5]}
		]
		
		transform_text = element.attribute('transform').value
		assert_no_match /garbage/, transform_text, 'old data remains'
		assert_not_nil /translate/.match(transform_text)
		assert_not_nil /skewY/.match(transform_text)

		transformer.set_transform_attribute element, []
		assert element.attribute('transform').nil?


	end

end

module TransformApplyerTestUtil
	include DOMTestUtil

	def stub_helper_matrix_of_enlarge_twice(helper)
		stub(helper).matrix_of {Matrix.affine_columns [
			[2, 0],[0, 2],[0, 0]
		]}
	end

	def stub_style_codec(codec)
		stub(codec).decode {[]}
		stub(codec).encode {'stub style text'}
		stub(codec).apply! {}
	end

	def create_svg_element(name, style = 'dummy')
		element = REXML::Element.new name
		element.add_attribute 'style', style

		element
	end
end

class PathTransformTest < Test::Unit::TestCase
	include TransformApplyerTestUtil
	
	sub_test_case 'applyer for path' do
		def test_apply_enlarge
			applyer = TransformApplyer_path.new
			stub_helper_matrix_of_enlarge_twice applyer.helper
			stub_matrix = applyer.helper.matrix_of nil

			stub_style_codec(applyer.style_codec)

			element = create_svg_element('path')
			element.add_attribute 'd', 'm 1,2 3,4 l 5,6'

			instructions = Array.new(2) {|i|
				PathInstruction::InstructionBase.new('dummy')
			}

			stub(applyer.codec).decode_path_data {
				instructions
			}

			mock(instructions[0]).apply!(stub_matrix) {}
			mock(instructions[1]).apply!(stub_matrix) {}


			stub(applyer.codec).encode_path_data {
				'dummy1 dummy2'
			}

			applyer.apply element, 'dummy (^_-)'

			assert_equal 'dummy1 dummy2', element.attribute('d').value()

		end
	end
end

class ShapeTransformTest < Test::Unit::TestCase
	include TransformApplyerTestUtil
		
	sub_test_case 'applyer for circle' do

		def test_apply_enlarge
			applyer = TransformApplyer_circle.new
			stub_helper_matrix_of_enlarge_twice applyer.helper
			
			stub_style_codec(applyer.style_codec)
			
			element = create_svg_element('circle')
			element.add_attribute 'cx', 3
			element.add_attribute 'cy', 5
			element.add_attribute 'r' , 1

			applyer.apply element, 'dummy (1,1)'

			assert_float_attr element,  6, 'cx'
			assert_float_attr element, 10, 'cy'
			assert_float_attr element,  2, 'r'
		end
	end

	sub_test_case 'applyer for rect' do

		def test_apply_enlarge_rx_ry_exists
			applyer = TransformApplyer_rect.new
			stub_helper_matrix_of_enlarge_twice applyer.helper
			
			stub_style_codec(applyer.style_codec)
			element = create_svg_element('rect')

			element.add_attribute 'x', 3
			element.add_attribute 'y', 5
			element.add_attribute 'rx' , 1
			element.add_attribute 'ry' , 1.2
			element.add_attribute 'width' ,  2 
			element.add_attribute 'height' , 7 

			applyer.apply element, 'dummy (1,1)'

			assert_float_attr element,  6, 'x'
			assert_float_attr element, 10, 'y'
			assert_float_attr element,  2, 'rx'
			assert_float_attr element,2.4, 'ry'
			assert_float_attr element,  4, 'width'
			assert_float_attr element, 14, 'height'
		end
		
		def test_apply_enlarge_only_rx_or_ry_exists
			applyer = TransformApplyer_rect.new
			stub_helper_matrix_of_enlarge_twice applyer.helper
			
			stub_style_codec(applyer.style_codec)
			element = create_svg_element('rect')
			
			element.add_attribute 'rx' , 1
			applyer.apply element, 'dummy (1,1)'
			assert_float_attr element,  2, 'rx'
			assert_float_attr element,  2, 'ry'

			element.delete_attribute 'rx'

			element.add_attribute 'ry', 3
			applyer.apply element, 'dummy (1,1)'
			assert_float_attr element,  6, 'rx'
			assert_float_attr element,  6, 'ry'
		end

		def test_apply_enlarge_rx_and_ry_dont_exists
			applyer = TransformApplyer_rect.new
			stub_helper_matrix_of_enlarge_twice applyer.helper
			
			stub_style_codec(applyer.style_codec)
			element = create_svg_element('rect')
			
			applyer.apply element, 'dummy (1,1)'
			assert_float_attr element,  0, 'rx'
			assert_float_attr element,  0, 'ry'

		end
	end
end

