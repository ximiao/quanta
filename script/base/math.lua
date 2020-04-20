--math.lua

function quanta_extend.round(n)
    return math.floor(0.5 + n)
end

function quanta_extend.rand(n1, n2)
    return math.random(n1 * 1000000, n2 * 1000000)/1000000
end

--区间检查
function quanta_extend.region(n, min, max)
    if n < min then
        return min
    elseif n > max then
        return max
    end
    return n
end

function quanta_extend.max(n, max)
    if n < max then
        return max
    end
    return n
end

function quanta_extend.min(n, min)
    if n > min then
        return min
    end
    return n
end
