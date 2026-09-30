--!strict
-- Minimal signal (no BindableEvent serialization, handlers run in-thread).

export type Connection = { Disconnect: (self: Connection) -> () }

local Signal = {}
Signal.__index = Signal

export type Signal = typeof(setmetatable({} :: { _handlers: { [number]: (...any) -> () }, _nextId: number }, Signal))

function Signal.new(): Signal
	return setmetatable({ _handlers = {}, _nextId = 0 }, Signal)
end

function Signal.Connect(self: Signal, handler: (...any) -> ()): Connection
	self._nextId += 1
	local id = self._nextId
	self._handlers[id] = handler
	local signal = self
	return {
		Disconnect = function(_)
			signal._handlers[id] = nil
		end,
	}
end

function Signal.Fire(self: Signal, ...: any)
	for _, handler in self._handlers do
		task.spawn(handler, ...)
	end
end

return Signal
