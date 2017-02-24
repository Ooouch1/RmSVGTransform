require 'test/unit'
require 'test/unit/rr' # not a default package

require '../src/rmSvgTrns'
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
			stub(@factory.parser).parse {[
				{key:'matrix', values:[0,1,2,3,4,5]}
			]}

			matrix = @factory.create ['dummy()']
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
			stub(@factory.parser).parse {[
				{key:'rotate', values:[-Math::PI/4]}
			]}
			
			matrix = @factory.create ['dummy()']
			# p = matrix * Vector[1, 0, 1]
			p = matrix.affine Vector[1, 0]
			
			assert_float_eq  Math.sqrt(2)/2, p[0]
			assert_float_eq -Math.sqrt(2)/2, p[1]


		end
		
		test 'rotate: center is indicated' do
			stub(@factory.parser).parse {[
				{key:'rotate', values:[-Math::PI/4, 1, 1]}
			]}
			
			matrix = @factory.create ['dummy()']
			$test_logger.info('Factory:single_transform, rotate with center') {matrix}
			p = matrix.affine Vector[1, 0]
			
			assert_float_eq 1 - Math.sqrt(2)/2, p[0], 'test on x'
			assert_float_eq 1 - Math.sqrt(2)/2, p[1], 'test on y'

	
		end
	end

	
end
