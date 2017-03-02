require_relative '../src/style'
require 'test/unit'
require 'test/unit/rr'
require_relative 'testlib'

require_relative '../src/matrix_ext'

class AttributeTest < Test::Unit::TestCase

	def test_stroke_width
		c = Math.cos(Math::PI/3)
		s = Math.sin(Math::PI/3)
		matrix = Matrix.affine_columns [
			[2*c, s],
			[-s, 2*c],
			[1, 1]
		]
		det = 4*c*c + s*s

		stroke_width = Style::StrokeWidth.new('stroke-width', '1')
		stroke_width.apply! matrix

		assert_float_eq Math.sqrt(det), stroke_width.value

	end

end
