
class Object
	def proxy_if_nil(proxy)
		if self.nil? then proxy else self end
	end

	def zero_if_nil
		proxy_if_nil(0)
	end
end

