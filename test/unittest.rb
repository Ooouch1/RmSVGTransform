require '../src/rmSvgTrns'

require 'test/unit'
require 'test/unit/rr' # not a default package

require 'logger'

$test_logger = Logger.new(STDOUT)

def assert_array_equal(expected_array, actual_array)
	for i in 0...expected_array.length
		msg =  'array_equal @ ' + i.to_s() + 'th element of ' +
			actual_array.to_s()
		assert_equal expected_array[i], actual_array[i], msg
	end
end

EPS = 1e-6
def assert_float_eq(expected, actual, msg = '')
	assert (actual - expected).abs < EPS, msg + 
		', expected:' + expected.to_s() + ' actual:' + actual.to_s
end
	
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


class MatrixFactoryTest < Test::Unit::TestCase
	sub_test_case 'single_transform' do
		setup do
			@factory = TransformMatrixFactory.new()
		end

		test 'matrix' do
			matrix = @factory.create({key:'matrix', values:[0,1,2,3,4,5]})
			$test_logger.info('Factory:single_transform, matrix') {matrix}

			assert_elem = -> (v, i, j) {
				assert_equal v, matrix[i, j], '@'+ i.to_s() +',' + j.to_s()
			}

			assert_elem [0, 0,0]
			assert_elem [1, 1,0]
			assert_elem [0, 2,0]

			assert_elem [2, 0,1]
			assert_elem [3, 1,1]
			assert_elem [0, 2,1]

			assert_elem [4, 0,2]
			assert_elem [5, 1,2]
			assert_elem [1, 2,2]
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


class TransformerTest < Test::Unit::TestCase
	class StubTransformApplyer < TransformApplyerBase
		def apply (svg_element, parse_result)
			'stub'
		end
	end

	def test_disable_skew
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
			]
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

class TransformApplyer_circleTest < Test::Unit::TestCase
	def test_apply_transform
		applyer = TransformApplyer_circle.new
		stub(applyer.helper).matrix_of {Matrix.affine_columns [
			[2, 0],[0, 2],[0, 0]
		]}
		
		element = REXML::Element.new 'circle'
		element.add_attribute 'cx', 3
		element.add_attribute 'cy', 5
		element.add_attribute 'r' , 1

		applyer.apply element, 'dummy (1,1)'

		assert_float_attr = -> (expected, name) {
			assert_float_eq expected, element.attribute(name).value.to_f
		}
		assert_float_attr [2, 'r']
		assert_float_attr [6, 'cx']
		assert_float_attr [10, 'cy']

	end
end
