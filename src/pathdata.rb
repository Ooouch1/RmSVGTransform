require_relative './matrix_ext'
require 'logger'


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
		attr_reader :logger
		attr_reader :instruction, :relative_coord, :instruction_order
		def initialize(instruction_char, instruction_order = -1)
			@instruction = SingleValue.new(instruction_char)
			@relative_coord = (instruction_char == instruction_char.downcase)
			@instruction_order = instruction_order
			@_first_instruction = (instruction_order == 0) 
			
			@logger = Logger.new(STDERR)
			logger.level = Logger::WARN
		end

		def encode
			(to_a.map {|token| token.encode}).join(' ')
		end

		def to_abs_instruction(pen_position_vec)
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
					coord_token.value, @relative_coord)
			end
		end

		def apply_to_diff(matrix, diff_token, dim)
			diff_token.value = matrix.affine_diff(diff_token.value, dim)
		end
=begin	
		def apply_to_diffs(matrix, diffs_token)
			diffs_token.value = matrix.affine_diffs(diffs_token.value)
		end
=end
		def apply_to_lengths(matrix, lengths_token)
			lengths_token.value = matrix.affine_lengths(lengths_token.value)
			.map { |l| l}
		end

		private
		attr_writer :relative_coord, :instruction
	end

	class Arc < InstructionBase
		attr_reader :value_sets
		def initialize(instruction_char, values, instruction_order)
			super(instruction_char, instruction_order)
			
			@value_sets = []

			slice_by_length(values, 7).each do |v_set|
				@value_sets.push({
					length_pair: Sequence.new(Vector[v_set[0], v_set[1]]),
					point:  Sequence.new(Vector[v_set[5], v_set[6]]),
					other_values: v_set[2..4].map {|v| SingleValue.new(v.to_i)}
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
			{instruction:instruction, value_sets: @value_sets}.to_s
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
		
		def last_point_vec
			@value_sets.last[:point].value
		end
		
		protected
		attr_writer :value_sets
	end

	class MultiPoint < InstructionBase
		attr_reader :points
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
			[instruction, @points].flatten
		end
		

		def last_point_vec
			@points.last.value
		end

		protected
		attr_writer :points
	end

	class Unary < InstructionBase
		
		def initialize(instruction_char, values, dim)
			super(instruction_char)
			@dim = dim
			@coords = values.map {|v| SingleValue.new(v)}
		end

		def to_seq_coords
			@coords.map {|coord| Sequence.new((Vector.basis(size: 2, index:@dim) * coord.value))}
		end
		
		def to_abs_seq_coords(pen_position_vec)
			seq_coords = to_seq_coords
			abs_coords = to_seq_coords
			if relative_coord
				abs_coords[0].value = seq_coords[0].value + pen_position_vec
				for i in 1...@coords.size 
					abs_coords[i].value = abs_coords[i-1] + seq_coords[i].value
				end
			else
				opposite = @dim == 0 ? 1 : 0
				abs_coords.each do |abs_coord|
					abs_coord.value[opposite] = pen_position_vec[opposite]
				end
			end
			
			return abs_coords
		end
		
		def apply!(matrix)
			logger.info "apply matrix to #{@instruction} #{@coords}"
			seq_coords = to_seq_coords
			seq_coords.each {|seq_coord| apply_to_coord matrix, seq_coord}
			@coords = seq_coords.map {|seq_coord| SingleValue.new(seq_coord.value[@dim])}
			@coords
		end

		def encode
			@instruction.to_s + ' ' + @coords.to_s
		end

		def to_s
			{instruction:@instruction, coords: @coords}.to_s
		end
		
		def to_a
			[instruction, @coords].flatten
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
			instruction
		end

		def to_a
			[instruction]
		end		
	end
end



module PathData
	class InstructionA < PathInstruction::Arc
		include PathInstruction
		
		def to_abs_coord(pen_position_vec)
			pen = Sequence.new(pen_position_vec)
			abs_value_sets = Marshal.load(Marshal.dump(value_sets))

			if relative_coord
				abs_value_sets[0][:point] = Sequence.new(pen.value + value_sets[0][:point].value)
				abs_value_sets[0][:previous_position] = Marshal.load(Marshal.dump(pen))
				for i in 1...@value_sets.size
					abs_value_sets[i][:point] = Sequence.new(value_sets[i][:point].value + abs_value_sets[i - 1][:point].value)
					abs_value_sets[i][:previous_position] = abs_value_sets[i - 1][:point]
				end
			else
				abs_value_sets[0][:previous_position] = Marshal.load(Marshal.dump(pen))
				for i in 1...@value_sets.size
					abs_value_sets[i][:previous_position] = abs_value_sets[i - 1][:point]
				end
			end

			abs_value_sets.each do |abs_value_set|
				computed_values = compute_center_and_angle_diff(abs_value_set[:length_pair].value, abs_value_set[:previous_position].value, abs_value_set[:point].value, abs_value_set[:other_values][1].value, abs_value_set[:other_values][2].value)
				abs_value_set[:center] = computed_values[:center]
				abs_value_set[:angle_diff] = computed_values[:angle_diff]
			end

			return abs_value_sets
		end
		
		# see: https://www.w3.org/TR/SVG/implnote.html#ArcImplementationNotes
		def compute_center_and_angle_diff(length_pair, previous_position, position, large_arc_flag, sweep_flag)
			v = (previous_position - position) / 2

			vx = v[0]
			vy = v[1]

			rx = length_pair[0]
			ry = length_pair[1]
			
			rx_sq = rx * rx
			ry_sq = ry * ry
			
			vx_sq = vx * vx
			vy_sq = vy * vy
						
			upper = rx_sq * ry_sq - rx_sq * vy_sq - ry_sq * vx_sq
			lower = rx_sq * vy_sq + ry_sq * vx_sq
			
			rate = upper / lower
			if rate < 0
				throw StandardError.new "negative value in sqrt #{rate}"
			end
			moved_center = Math.sqrt(rate) * (Vector.elements([rx * vy / ry, -ry * vx / rx]))
			if large_arc_flag == sweep_flag
				moved_center *= -1
			end
			center = moved_center + (previous_position + position) / 2

			logger.debug({prev: previous_position, pos: position, vx: vx, vy: vy, rx: rx, ry: ry, cx: center[0], cy: center[1]})

			a = v - moved_center
			a[0] /= rx
			a[1] /= ry
			
			b = -v - moved_center
			a[0] /= rx
			a[1] /= ry
			
			angle_diff = ((a[0] * b[1] - a[1] * b[0]) > 0 ? 1 : -1) * a.angle_with(b)

			{center: center, angle_diff: angle_diff}
		end
		
		def to_abs_instruction(pen_position_vec)
			a = InstructionA.new @instruction.value.upcase, [0,0,0,0,0,0,0], instruction_order
			a.value_sets = to_abs_coord(pen_position_vec)
			a
		end

		def apply!(matrix)
			super matrix
			apply_to_coord matrix, value_sets[0][:previous_position]
		end
	end
	
	class InstructionM < PathInstruction::MultiPoint
		include PathInstruction
		def initialize(instruction_char, values, instruction_order)
			super(instruction_char, values, instruction_order)
		end
		
		def to_abs_coord(pen_position_vec)
			pen = Sequence.new(pen_position_vec)
			if not relative_coord
				return @points
			end
		
			abs_coord = Array.new @points.size, Sequence.new(Vector.elements([0, 0]))
			abs_coord[0] = @_first_instruction ? @points[0] : pen
			for i in 1...@points.size
				abs_coord[i] = Sequence.new(@points[i].value + abs_coord[i-1].value)
			end
		
			return abs_coord
		end
		
		def to_abs_instruction(pen_position_vec)
			a = InstructionM.new @instruction.value.upcase, [0,0], instruction_order
			a.points = to_abs_coord(pen_position_vec)
			a
		end
	end
	
	class InstructionQ < PathInstruction::MultiPoint
		include PathInstruction
		def initialize(instruction_char, values, instruction_order)
			super(instruction_char, values, instruction_order)
			@point_sets = slice_by_length @points, 2
		end
		
		def to_abs_coord(pen_position_vec)
			pen = Sequence.new(pen_position_vec)
			if not relative_coord
				return @points
			end
			
			abs_coords = Array.new()
			@point_sets.each do |points|
				abs_coord = points.map {|p| Sequence.new(p.value + pen.value)}

				pen.value = abs_coord.last.value
				abs_coords.append abs_coord
			end
			
			return abs_coords.flatten
		end
		
		def to_abs_instruction(pen_position_vec)
			a = InstructionQ.new @instruction.value.upcase, [0,0,0,0], instruction_order
			a.points = to_abs_coord(pen_position_vec)
			a
		end
	end

	class InstructionT < PathInstruction::MultiPoint
		include PathInstruction
		def initialize(instruction_char, values, instruction_order)
			super(instruction_char, values, instruction_order)
			@point_sets = slice_by_length @points, 1
		end
		
		def to_abs_coord(pen_position_vec)
			pen = Sequence.new(pen_position_vec)
			if not relative_coord
				return @points
			end
			
			abs_coords = Array.new()
			@point_sets.each do |points|
				abs_coord = points.map {|p| Sequence.new(p.value + pen.value)}

				pen.value = abs_coord.last.value
				abs_coords.append abs_coord
			end
			
			return abs_coords.flatten
		end
		
		def to_abs_instruction(pen_position_vec)
			a = InstructionS.new @instruction.value.upcase, [0,0], instruction_order
			a.points = to_abs_coord(pen_position_vec)
			a
		end
	end

	class InstructionC < PathInstruction::MultiPoint
		include PathInstruction
		def initialize(instruction_char, values, instruction_order)
			super(instruction_char, values, instruction_order)
			@point_sets = slice_by_length @points, 3
		end
		
		def to_abs_coord(pen_position_vec)
			pen = Sequence.new(pen_position_vec)
			if not relative_coord
				return @points
			end
			
			abs_coords = Array.new()
			@point_sets.each do |points|
				abs_coord = points.map {|p| Sequence.new(p.value + pen.value)}

				pen.value = abs_coord.last.value
				abs_coords.append abs_coord
			end
			
			return abs_coords.flatten
		end
		
		def to_abs_instruction(pen_position_vec)
			a = InstructionC.new @instruction.value.upcase, [0,0,0,0,0,0], instruction_order
			a.points = to_abs_coord(pen_position_vec)
			a
		end
	end

	class InstructionS < PathInstruction::MultiPoint
		include PathInstruction
		def initialize(instruction_char, values, instruction_order)
			super(instruction_char, values, instruction_order)
			@point_sets = slice_by_length @points, 2
		end
		
		def to_abs_coord(pen_position_vec)
			pen = Sequence.new(pen_position_vec)
			if not relative_coord
				return @points
			end
			
			abs_coords = Array.new()
			@point_sets.each do |points|
				abs_coord = points.map {|p| Sequence.new(p.value + pen.value)}

				pen.value = abs_coord.last.value
				abs_coords.append abs_coord
			end
			
			return abs_coords.flatten
		end
		
		def to_abs_instruction(pen_position_vec)
			a = InstructionS.new @instruction.value.upcase, [0,0,0,0], instruction_order
			a.points = to_abs_coord(pen_position_vec)
			a
		end
	end

	class InstructionL < PathInstruction::MultiPoint
		include PathInstruction
		def initialize(instruction_char, values, instruction_order)
			super(instruction_char, values, instruction_order)
		end
		
		def to_abs_coord(pen_position_vec)
			pen = Sequence.new(pen_position_vec)
			if not relative_coord
				return @points
			end
		
			abs_coord = Array.new @points.size, Sequence.new(Vector.elements([0, 0]))
			abs_coord[0] = Sequence.new(@points[0].value + pen.value)
			for i in 1...@points.size
				abs_coord[i] = Sequence.new(@points[i].value + abs_coord[i-1].value)
			end
		
			return abs_coord
		end
		
		def to_abs_instruction(pen_position_vec)
			a = InstructionL.new @instruction.value.upcase, [0,0], instruction_order
			a.points = to_abs_coord(pen_position_vec)
			a
		end
	end

	class InstructionH < PathInstruction::Unary
		def initialize(instruction_char, values, instruction_order)
			super(instruction_char, values, 0)
		end
		
		def to_instructionL(pen_position_vec)
			abs_coords = to_abs_seq_coords pen_position_vec
			coord_array = (abs_coords.map {|coord| coord.value.to_a}).flatten
			InstructionL.new('L', coord_array, instruction_order)
		end
	end

	class InstructionV < PathInstruction::Unary
		def initialize(instruction_char, values, instruction_order)
			super(instruction_char, values, 1)
		end
		def to_instructionL(pen_position_vec)
			abs_coords = to_abs_seq_coords pen_position_vec
			coord_array = (abs_coords.map {|coord| coord.value.to_a}).flatten
			InstructionL.new('L', coord_array, instruction_order)
		end
	end

	class InstructionZ < PathInstruction::Parameterless
		def to_abs_instruction(pen_position_vec)
			@_pen_position_vec = pen_position_vec
			self
		end
		def last_point_vec
			@_pen_position_vec
		end

	
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
