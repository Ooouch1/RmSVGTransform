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
			return Vector.elements affine_lengths(vector)
		end


		computed = self * Vector.elements(vector.to_a() + [1], false)
		Vector.elements [computed[0], computed[1]]
	end

	def affine_length(length, dim)
		create_basis = -> () {}
		v = Vector.basis(size: column_count-1, index:dim) * length
		z = Vector.elements [0]*(column_count-1)

		# affine is not linear mapping due to translation
		(affine(v) - affine(z)).norm
	end

	def affine_lengths(lengths)
		if lengths.size != column_count-1
			raise ArgumentError, "The size of parameter 'lengths' " +
				"should be column_count-1"
		end
		lengths.each_with_index.map { |l, i|
			affine_length(l, i)
		}
	end

end


