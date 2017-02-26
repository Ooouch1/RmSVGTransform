require 'matrix'

class Matrix
	def Matrix.affine_columns(cols)
		affine_cols = cols.map {|col| col + [0]}
		affine_cols[cols.length-1][cols[0].length] = 1
		Matrix.columns affine_cols
	end

	def affine(vector)
		if vector.count != column_count - 1
			raise ArgumentError, 'size mismatch'
		end
		computed = self * Vector.elements(vector.to_a() + [1], false)
		Vector.elements [computed[0], computed[1]]
	end
end


