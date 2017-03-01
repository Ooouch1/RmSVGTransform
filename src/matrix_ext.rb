require 'matrix'

class Matrix
	def Matrix.affine_columns(cols)
		affine_cols = cols.map {|col| col + [0]}
		affine_cols.last()[-1] = 1
		Matrix.columns affine_cols
	end

	def affine(vector, relative_coord = false)
		if vector.count != column_count - 1
			raise ArgumentError, 'size mismatch'
		end

		if relative_coord
			return Vector.elements affine_diffs(vector)
		end


		computed = self * Vector.elements(vector.to_a() + [1], false)
		Vector.elements [computed[0], computed[1]]
	end

	def affine_diff(diff, dim)
		create_basis = -> () {}
		v = Vector.basis(size: column_count-1, index:dim) * diff
		z = Vector.elements [0]*(column_count-1)

		# affine is not linear mapping due to translation
		(affine(v) - affine(z))[dim]
	end

	def affine_diffs(diffs)
		if diffs.size != column_count-1
			raise ArgumentError, "The size of parameter 'lengths' " +
				"should be column_count-1"
		end
		diffs.each_with_index.map { |d, i|
			affine_diff(d, i)
		}
	end

end


