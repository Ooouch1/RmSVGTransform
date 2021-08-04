require_relative '../src/pathdata'
require 'test/unit'
require 'test/unit/rr'

require_relative './testlib'

module InstructionAsserts
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
		assert_equal expected_arrays.length, instructions.length,
			'different item count'
		expected_arrays.each_with_index do |ex, i|
			assert_instruction_as_array ex, instructions[i]
		end
	end

end

class PathCodecTest < Test::Unit::TestCase
	include InstructionAsserts	

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
				['a', vec(0,1), 2, 3, 4, vec(5, 6)],
				['h', 7],
				['v', 0.8]
			]
			instructions = @codec.decode_path_data(
				'a 0,1,2,3,4,5,6 h7.0 v 8e-1')
			
			assert_instructions_as_array answer, instructions
		end
	end

	
	sub_test_case 'decode path M(1,2) L(3,4)(5,6) z' do
		setup do
			@answer = [
				['M', vec(1, 2)],
				['L', vec(3, 4), vec(5, 6)],
				['z']
			]
		end

		def test_comma_separation_and_space_for_value_style
			instructions = @codec.decode_path_data('M 1 2, L 3 4 5 6, z')
			assert_instructions_as_array @answer, instructions
		end

		def test_space_separation_and_comma_for_value_style
			instructions = @codec.decode_path_data('M1,2 L 3,4,5,6z')
			assert_instructions_as_array @answer, instructions
		end
	end

	sub_test_case 'encode path M(1,2) L(3,4)(5,6) z' do
		def test_encode
			create_stub = ->() {stub()}
			instructions = Array.new(3) { |i|
				PathInstruction::InstructionBase.new('dummy')
			}

			stub(instructions[0]).encode {'M 1,2'}
			stub(instructions[1]).encode {'L 3,4 5,6'}
			stub(instructions[2]).encode {'z'}

			text = @codec.encode_path_data(instructions)
			assert_equal 'M 1,2 L 3,4 5,6 z', text
		end
	end

end

class InstructionConversionTest < Test::Unit::TestCase
	include InstructionAsserts
	
	sub_test_case 'to_abs_instruction m(0,1)(2,3)' do
		def test_to_abs_instruction
			answer = ['M', vec(0, 1), vec(2, 4)]
			instruction = PathData::InstructionM.new('m', [0,1,2,3], 0)
			assert_instruction_as_array answer, instruction.to_abs_instruction(vec(0,0))
		end
	end

end

class InstructionTransformTest < Test::Unit::TestCase
	include InstructionAsserts	
	
	def verify_transform(answer, inst)
		inst.apply! @matrix
		assert_instruction_as_array answer, inst 
	end

	sub_test_case 'arc instruction' do
		setup do
			@matrix = Matrix.affine_columns [
				[2, 0],
				[0, 3],
				[4, 5],
			]

		end


		def test_relative_coord
			verify_transform ['a', vec(2,6), 3, 4, 5, vec(12, 21)],
				PathData::InstructionA.new('a', [1,2, 3,4,5, 6,7], 1)
		end

		def test_absolute_coord
			verify_transform ['A', vec(2.0,6.0), 3, 4, 5, vec(16, 26)],
				PathData::InstructionA.new('A', [1,2, 3,4,5, 6,7], 1)
		end
	end

	sub_test_case 'the 1st value of the first moveto should be absolute coordinate' do
		setup do
			@matrix = Matrix.affine_columns [
				[2, 0],
				[0, 3],
				[4, 5],
			]

		end

		def test_relative_coord
			verify_transform ['m', vec(6, 11), vec(-12, 21)],
				PathData::InstructionM.new('m', [1,2, -6,7], 0)
		end

		def test_absolute_coord
			verify_transform ['M', vec(6, 11), vec(12+4, 21+5)],
				PathData::InstructionM.new('M', [1,2, 6,7], 0)
		end
	end


	sub_test_case 'rotate -PI/2' do 
		setup do
			@matrix = Matrix.affine_columns [
				[0, 1],
				[-1, 0],
				[3, 4],
			]
		end
		
		def test_relative_coord
			verify_transform ['m', vec(-2+3, 1+4), vec(-7, -6)],
				PathData::InstructionM.new('m', [1,2, -6,7], 0)
		end
	end
	
	sub_test_case 'horizontal move' do 
		setup do
			@matrix = Matrix.affine_columns [
				[2, 0],
				[0, 1],
				[0, 0],
			]
		end
		
		def test_absolute_coord
			verify_transform ['H', 6,14],
				PathData::InstructionH.new('H', [3,7], 0)
		end
	end
	

end

