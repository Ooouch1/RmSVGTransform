require_relative './matrix_ext'

module PathInstruction
	# tokens
	class Sequence
		attr_accessor :value
		def initialize(value)
			@value = value
		end

		def encode
			@value.to_a().join(',')
		end

		def to_s
			@value.to_s
		end
	end
	class SingleValue
		attr_accessor :value
		def initialize(value)
			@value = value
		end

		def encode
			@value
		end
		
		def to_s
			@value.to_s
		end
	end

	class InstructionBase
		def initialize(instruction_char, instruction_order = -1)
			@instruction = SingleValue.new(instruction_char)
			@_relative_coord = (instruction_char == instruction_char.downcase)
			@_first_instruction = (instruction_order == 0) 
		end

		def encode
			(to_a.map {|token| token.encode}).join(' ')
		end

		private
		def slice_by_length(values, length)
			values.each_slice(length).to_a
		end
		
		def slice_to_2D_coords(values)
			slice_by_length(values, 2)
			#values.values_at(
			#	* values.each_index.select {|i| i.even?}).zip(
			#	values.values_at(* values.each_index.select {|i| i.odd?}))
		end

		def apply_to_coord(matrix, coord_token, index = -1)
			if @_first_instruction && index == 0
				coord_token.value = matrix.affine(
					coord_token.value)
			else
				coord_token.value = matrix.affine(
					coord_token.value, @_relative_coord)
			end
		end

		def apply_to_length(matrix, length_token)
			length_token.value = matrix.affine_length(length_token.value)
		end
		
		def apply_to_lengths(matrix, lengths_token)
			lengths_token.value = matrix.affine_lengths(lengths_token.value)
		end
	end

	class Arc < InstructionBase
		
		def initialize(instruction_char, values, instruction_order)
			super(instruction_char, instruction_order)

			@instruction = SingleValue.new(instruction_char)
			@relative_coord = (instruction_char == instruction_char.downcase)
			
			@value_sets = []

			slice_by_length(values, 7).each do |v_set|
				@value_sets.push({
					length_pair: Sequence.new([v_set[0], v_set[1]]),
					point:  Sequence.new(Vector[v_set[5], v_set[6]]),
					other_values: v_set[2..4].map {|v| SingleValue.new(v)}
				})
			end
		end

		def apply!(matrix)
			@value_sets.each do |v_set|
				apply_to_lengths matrix, v_set[:length_pair]
				apply_to_coord   matrix, v_set[:point]
			end	
		end

		def to_s
			{instruction:@instruction, value_sets: @value_sets}.to_s
		end

		def to_a
			[@instruction, @value_sets.map { |v_set|
				[
					v_set[:length_pair],
				 	v_set[:other_values], 
					v_set[:point]
				]
			}].flatten
		end
	end

	class MultiPoint < InstructionBase
		
		def initialize(instruction_char, values, instruction_order)
			super(instruction_char, instruction_order)
			@points = slice_to_2D_coords(values).map { |coord|
				Sequence.new(Vector.elements coord)
			}
		end

		def apply!(matrix)
			@points.each_with_index do |point, i|
				apply_to_coord matrix, point, i
			end
		end

		def to_s
			{instruction:@instruction, points: @points}.to_s
		end

		def to_a
			[@instruction, @points].flatten
		end
	end

	class Unary < InstructionBase
		
		def initialize(instruction_char, values, dim)
			super(instruction_char)
			@dim = dim
			@coord = SingleValue.new(values.last)
		end

		def apply!(matrix)
			apply_to_length matrix, @coord 
			#TODO fix to use apply_to_coord. it needs to receive current pen position...
		end

		def encode
			@instruction + ' ' + @coord
		end

		def to_s
			{instruction:@instruction, coord: @coord}.to_s
		end
		
		def to_a
			[@instruction, @coord]
		end
	end

	class Parameterless < InstructionBase
		def initialize(instruction_char, value_dummy = nil,
					   instruction_order_dummy = nil)
			super(instruction_char)
		end

		def apply!(matrix)
		end

		def to_s
			@instruction
		end

		def to_a
			[@instruction]
		end
	end
end



module PathData
	class InstructionA < PathInstruction::Arc
	end
	class InstructionM < PathInstruction::MultiPoint
	end
	class InstructionQ < PathInstruction::MultiPoint
	end
	class InstructionT < PathInstruction::MultiPoint
	end
	class InstructionC < PathInstruction::MultiPoint
	end
	class InstructionS < PathInstruction::MultiPoint
	end
	class InstructionL < PathInstruction::MultiPoint
	end

	class InstructionH < PathInstruction::Unary
		def initialize(instruction_char, values, instruction_order)
			super(instruction_char, values, 0)
		end
	end
	class InstructionV < PathInstruction::Unary
		def initialize(instruction_char, values, instruction_order)
			super(instruction_char, values, 1)
		end
	end

	class InstructionZ < PathInstruction::Parameterless
	end



	class InstructionFactory
		def create(instruction_char, values, instruction_order)
			clss = eval "Instruction#{instruction_char.upcase}"
			clss.new(instruction_char, values, instruction_order)
		end
	end

	class Codec
		@@REG_NUM_STR = "[+-]?\\d+(\\.\\d+)?([eE][+-]?\\d+)?".freeze

		def initialize
			@instruction_factory = InstructionFactory.new
		end
		
		def decode_path_data(path_data_text)
			reg = /(((\w)((\s|,)*#{@@REG_NUM_STR})*))/
			instruction_texts = longest_matches(path_data_text, reg)
			instruction_texts.each_with_index.map { |t, i|
				decode_instruction_text(t, i)
			}
		end

		def decode_instruction_text(text, instruction_order)
			values = longest_matches(text, /(#{@@REG_NUM_STR})/)
			.map {|m| m.to_f}

			@instruction_factory.create(text[0], values, instruction_order)
		end

		def encode_path_data(instructions)
			texts = instructions.map {|inst| inst.encode}
			texts.join(' ')
		end

		private
		def longest_matches(text, reg)
			text.scan(reg).map! {|m| m[0]}
		end
	end

end
