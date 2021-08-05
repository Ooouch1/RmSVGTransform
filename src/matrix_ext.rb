require 'matrix'

class Matrix
	def Matrix.affine_columns(cols)
		affine_cols = cols.map {|col| col + [0]}
		affine_cols.last()[-1] = 1
		Matrix.columns affine_cols
	end

	def affine(vector, relative_coord = false)
		if vector.count != column_count - 1
			raise ArgumentError, "size mismatch, vector: #{vector}, column_count: #{column_count}"
		end

		if relative_coord
			return Vector.elements affine_point_diff(vector)
		end


		computed = self * Vector.elements(vector.to_a() + [1], false)
		Vector.elements [computed[0], computed[1]]
	end

	def affine_diff(diff, dim)
		v = Vector.basis(size: column_count-1, index:dim) * diff
		z = Vector.elements [0]*(column_count-1)

		# affine is not linear mapping due to translation
		(affine(v) - affine(z))[dim]
	end

	def affine_point_diff(diff)
		if diff.size != column_count-1
			raise ArgumentError, "The size of parameter 'lengths' " +
				"should be column_count-1"
		end

		v = Vector.elements diff.to_a

		(affine(v) - affine(Vector.elements [0] * diff.size))
	end

	def affine_lengths(lengths)
		if lengths.size != column_count-1
			raise ArgumentError, "The size of parameter 'lengths' " +
				"should be column_count-1"
		end

		v0 = Vector.elements [lengths[0], 0]
		v1 = Vector.elements [0, lengths[1]]

		w0 = (affine(v0) - affine(Vector.elements [0] * lengths.size))
		w1 = (affine(v1) - affine(Vector.elements [0] * lengths.size))
		
		Vector.elements [w0.norm, w1.norm]
	end

end


