local Public={}

--Encodes string to double
function Public.encode_string_to_double(str) 
    assert(#str <= 8, "String length exceeds 8 characters; cannot encode.")
    
    local result = 0
    local length = #str
    local max_bytes = 8 -- We can encode up to 8 bytes in a double precision floating point
    
    for i = 1, length do
        local byte = string.byte(str, i)
        result = result + byte * (256 ^ (i - 1))
    end
    
    return result
end

-- Decodes a double back into a string
function Public.decode_double_to_string(num)
    local result = {}
    local max_bytes = 8 -- Decode up to 8 bytes
    
    for i = 0, max_bytes - 1 do
        local byte = math.floor(num / (256 ^ i)) % 256
        if byte == 0 then break end -- Null terminator or end of meaningful bytes
        table.insert(result, string.char(byte))
    end
    
    return table.concat(result)
end

function Public.merge(old, new)
	old = util.table.deepcopy(old)

	for k, v in pairs(new) do
		if v == "nil" then
			old[k] = nil
		else
			old[k] = v
		end
	end

	return old
end

Public.find = function(tbl, f, ...)
	if type(f) == "function" then
		for k, v in pairs(tbl) do
			if f(v, k, ...) then
				return v, k
			end
		end
	else
		for k, v in pairs(tbl) do
			if v == f then
				return v, k
			end
		end
	end
	return nil
end

return Public

