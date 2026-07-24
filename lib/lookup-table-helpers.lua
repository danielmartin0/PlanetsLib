local Public = {}

local function interpolate(x, y, xi, extrapolate)
    local n = #x

    -- Handle outside range
    if xi < x[1] then
        if not extrapolate then
            return nil
        end
        return y[1] + (xi - x[1]) * (y[2] - y[1]) / (x[2] - x[1])
    elseif xi > x[n] then
        if not extrapolate then
            return nil
        end
        return y[n-1] + (xi - x[n-1]) * (y[n] - y[n-1]) / (x[n] - x[n-1])
    end

    -- Exact endpoints
    if xi == x[1] then return y[1] end
    if xi == x[n] then return y[n] end

    -- Binary search
    local lo, hi = 1, n
    while hi - lo > 1 do
        local mid = math.floor((lo + hi) / 2)
        if xi < x[mid] then
            hi = mid
        else
            lo = mid
        end
    end

    -- Linear interpolation
    local t = (xi - x[lo]) / (x[hi] - x[lo])
    return y[lo] + t * (y[hi] - y[lo])
end

function Public.interp1(x, y, xi, extrapolate)
    if type(xi) == "table" then
        local out = {}
        for i = 1, #xi do
            out[i] = interpolate(x, y, xi[i], extrapolate)
        end
        return out
    else
        return interpolate(x, y, xi, extrapolate)
    end
end

return Public