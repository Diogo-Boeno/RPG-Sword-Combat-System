--[[
	Signal
	Sinal lightweight (sem BindableEvent).

	API:
		local sig = Signal.new()
		local conn = sig:Connect(function(...) end)
		sig:Fire(...)
		sig:Wait()
		sig:Once(fn)
		conn:Disconnect()
		sig:DisconnectAll()
		sig:Destroy()
--]]

local Signal = {}
Signal.__index = Signal

local Connection = {}
Connection.__index = Connection

function Connection.new(signal, fn)
	return setmetatable({
		_signal = signal,
		_fn = fn,
		Connected = true,
	}, Connection)
end

function Connection:Disconnect()
	if not self.Connected then return end
	self.Connected = false
	local conns = self._signal._connections
	for i, c in ipairs(conns) do
		if c == self then
			table.remove(conns, i)
			break
		end
	end
end

function Signal.new()
	return setmetatable({
		_connections = {},
	}, Signal)
end

function Signal:Connect(fn)
	assert(type(fn) == "function", "[Signal] Connect espera function")
	local conn = Connection.new(self, fn)
	table.insert(self._connections, conn)
	return conn
end

function Signal:Fire(...)
	-- clone pra evitar problemas se algum handler se disconnect durante o fire
	local snapshot = table.clone(self._connections)
	for _, conn in ipairs(snapshot) do
		if conn.Connected then
			task.spawn(conn._fn, ...)
		end
	end
end

function Signal:Wait()
	local thread = coroutine.running()
	local conn
	conn = self:Connect(function(...)
		conn:Disconnect()
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:Once(fn)
	local conn
	conn = self:Connect(function(...)
		conn:Disconnect()
		fn(...)
	end)
	return conn
end

function Signal:DisconnectAll()
	for _, c in ipairs(self._connections) do
		c.Connected = false
	end
	table.clear(self._connections)
end

function Signal:Destroy()
	self:DisconnectAll()
end

return Signal
