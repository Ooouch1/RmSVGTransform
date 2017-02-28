require 'test/unit'

class Test::Unit::TestCase
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


	def vec(x, y)
		Vector.elements [x,y]
	end
end	
