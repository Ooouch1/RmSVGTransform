require_relative '../src/pathdata'
require 'test/unit'
require 'test/unit/rr'

require_relative './testlib'

class PathCodecTest < Test::Unit::TestCase
	
	def assert_instruction_as_array(
		expected_array, actual_instruction)
		begin
			assert_array_equal expected_array,
				actual_instruction.to_a.map {|t| t.value}
		rescue NoMethodError => e
			p actual_instruction.to_a
			raise e
		end
	end
	def assert_instructions_as_array(expected_arrays, instructions)
		assert_equal expected_arrays.length, instructions.length, 'different item count'
		expected_arrays.each_with_index do |ex, i|
			assert_instruction_as_array ex, instructions[i]
		end
	end

	def setup
		@codec = PathData::Codec.new
	end

	sub_test_case 'decode path M(0,1)(3,4)(5,6)' do
		def test_decode
			answer = [['M', vec(0, 1), vec(3, 4), vec(5, 6)]]
			instructions = @codec.decode_path_data("M0,1 3,4  5,6")
			
			assert_instructions_as_array answer, instructions
		end
	end

	sub_test_case 'decode path a(0,1,2,3,4,5,6)h(7)v(8)' do
		def test_decode
			answer = [
				['a', [0,1], 2, 3, 4, vec(5, 6)],
				['h', 7],
				['v', 0.8]
			]
			instructions = @codec.decode_path_data(
				'a 0,1,2,3,4,5,6 h7.0 v 8e-1')
			
			assert_instructions_as_array answer, instructions
		end
	end
end

__END__
	
	sub_test_case 'decode path M(1,2) L(3,4)(5,6) z' do
		setup do
			@answer = ['M 1,2', 'L 3,4 5,6', 'z']
		end

		def test_comma_separation_and_space_for_value_style
			instructions = @codec.decode_path_data("M 1 2, L 3 4 5 6, z")
			assert_instruction_codes @answer, instructions
		end

		def test_space_separation_and_comma_for_value_style
			instructions = @codec.decode_path_data("M1,2 L 3,4,5,6z")
			assert_instruction_codes @answer, instructions
		end
	end

	sub_test_case 'encode path M(1,2) L(3,4)(5,6) z' do
		def test_encode
			instructions = [
				{instruction: 'M', points: [vec(1,2)]},
				{instruction: 'L', points: [vec(3,4), vec(5,6)]},
				{instruction: 'z', points: []}
			]
			text = @codec.encode_path_data(instructions)
			assert_equal 'M 1,2 L 3,4 5,6 z', text
		end
	end

end
