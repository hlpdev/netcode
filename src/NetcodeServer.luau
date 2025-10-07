--!optimize 2

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RootName = "Netcode"

local NetcodeBufferReader = require(script.Parent.NetcodeBufferReader)
local NetcodeBufferWriter = require(script.Parent.NetcodeBufferWriter)
local NetcodeTypes = require(script.Parent.NetcodeTypes)
local NetcodeUtils = require(script.Parent.NetcodeUtils)

type SchemaNode = NetcodeTypes.SchemaNode

local NetcodeServer = {}
NetcodeServer.__index = NetcodeServer

export type RouteEntry = {
	name: string,
	func: (...any) -> any,
	unreliable: boolean,
	schema: { SchemaNode },
	returnType: SchemaNode?,
}

export type NetcodeServer = {
	_tag: string,
	_isServer: boolean,
	_folder: Folder,

	_eventsIn: { [string]: RouteEntry },
	_funcsIn: { [string]: RouteEntry },
	_eventsOut: { [string]: RouteEntry },
	_funcsOut: { [string]: RouteEntry },

	addEvent: (self: NetcodeServer, name: string, fn: (...any) -> (), unreliable: boolean, ...SchemaNode) -> (),

	addFunction: (
		self: NetcodeServer,
		name: string,
		fn: (...any) -> any,
		returnType: SchemaNode,
		...SchemaNode
	) -> (),

	callEventForPlayer: (self: NetcodeServer, name: string, player: Player, ...any) -> (),
	callEventForPlayers: (self: NetcodeServer, name: string, players: { Player }, ...any) -> (),
	callEventForAll: (self: NetcodeServer, name: string, ...any) -> (),
	callEventForAllExcept: (self: NetcodeServer, name: string, excludedPlayer: Player, ...any) -> (),
	callEventForAllExceptAll: (self: NetcodeServer, name: string, excludedPlayers: { Player }, ...any) -> (),

	callFunction: (self: NetcodeServer, name: string, player: Player, ...any) -> any,

	describe: (
		self: NetcodeServer
	) -> {
		events: { [string]: { unreliable: boolean, schema: { SchemaNode } } },
		funcs: { [string]: { schema: { SchemaNode }, returnType: SchemaNode } },
	},
}

local function RootFolder(): Folder
	local root = ReplicatedStorage:FindFirstChild(RootName)

	if not root then
		root = Instance.new("Folder")
		root.Name = RootName
		root.Parent = ReplicatedStorage
	end

	return root
end

local function TagFolder(tag: string): Folder
	local root = RootFolder()
	local tagFolder = root:FindFirstChild(tag)

	if not tagFolder then
		tagFolder = Instance.new("Folder")
		tagFolder.Name = tag
		tagFolder.Parent = root
	end

	return tagFolder
end

local function Rename(prefix: string, name: string): string
	return prefix .. "_" .. name
end

local function GetRemoteEvent(folder: Folder, name: string): RemoteEvent
	local remote = folder:FindFirstChild(name)

	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end

	return remote
end

local function GetUnreliableRemoteEvent(folder: Folder, name: string): UnreliableRemoteEvent
	local remote = folder:FindFirstChild(name)

	if not remote then
		remote = Instance.new("UnreliableRemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end

	return remote
end

local function GetRemoteFunction(folder: Folder, name: string): RemoteFunction
	local remote = folder:FindFirstChild(name)

	if not remote then
		remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = folder
	end

	return remote
end

local function PackArgs(schema: { SchemaNode }, ...: any): (string, { any })
	return NetcodeUtils.packArgs(schema, ...)
end

local function GetControlFunction(folder: Folder): RemoteFunction
	local name = Rename("SYS", "Control")
	local remote = folder:FindFirstChild(name)
	if not remote then
		remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = folder
	end

	return remote
end

local function SnapshotEventsOut(self: NetcodeServer)
	local out = {}
	for name, r in pairs(self._eventsOut) do
		out[name] = {
			unreliable = r.unreliable,
			schema = r.schema,
		}
	end

	return out
end

local function SnapshotFunctionsOut(self: NetcodeServer)
	local out = {}
	for name, r in pairs(self._funcsOut) do
		out[name] = {
			schema = r.schema,
			returnType = r.returnType,
		}
	end

	return out
end

function NetcodeServer.new(tag: string): NetcodeServer
	assert(RunService:IsServer(), "NetcodeServer can only be used on the server.")

	local self = setmetatable({
		_tag = tag,
		_isServer = true,
		_folder = TagFolder(tag),

		_eventsIn = {},
		_eventsOut = {},
		_funcsIn = {},
		_funcsOut = {},
	}, NetcodeServer)

	local control = GetControlFunction(self._folder)
	control.OnServerInvoke = function(_: Player, req: any)
		local op = req and req.op

		if op == "describe" then
			return self:describe()
		elseif op == "registerEvent" then
			local name = req.name
			local unreliable = req.unreliable == true
			local schema = req.schema :: { SchemaNode }

			if not self._eventsOut[name] then
				self._eventsOut[name] = {
					name = name,
					func = function() end,
					unreliable = unreliable,
					schema = schema,
					returnType = nil,
				}
				local eventName = Rename(unreliable and "UE" or "E", name)
				if unreliable then
					GetUnreliableRemoteEvent(self._folder, eventName)
				else
					GetRemoteEvent(self._folder, eventName)
				end
			end
			return true
		elseif op == "registerFunction" then
			local name = req.name
			local schema = req.schema :: { SchemaNode }
			local returnType = req.returnType :: SchemaNode

			if not self._funcsOut[name] then
				self._funcsOut[name] = {
					name = name,
					func = function()
						return nil
					end,
					unreliable = false,
					schema = schema,
					returnType = returnType,
				}
				local fnName = Rename("F", name)
				GetRemoteFunction(self._folder, fnName)
			end
			return true
		elseif op == "getEvent" then
			local name = req.name
			local r = self._eventsOut[name]
			if not r then
				return nil
			end
			return {
				unreliable = r.unreliable,
				schema = r.schema,
			}
		elseif op == "getFunction" then
			local name = req.name
			local r = self._funcsOut[name]
			if not r then
				return nil
			end
			return {
				schema = r.schema,
				returnType = r.returnType,
			}
		elseif op == "getInboundEvent" then
			local name = req.name
			local r = self._eventsIn[name]
			if not r then
				return nil
			end
			return {
				unreliable = r.unreliable,
				schema = r.schema,
			}
		elseif op == "getInboundFunction" then
			local name = req.name
			local r = self._funcsIn[name]
			if not r then
				return nil
			end
			return {
				schema = r.schema,
				returnType = r.returnType,
			}
		else
			error("Unknown control op: " .. tostring(op))
		end
	end

	return self
end

function NetcodeServer.addEvent(
	self: NetcodeServer,
	name: string,
	fn: (...any) -> (),
	unreliable: boolean,
	...: SchemaNode
)
	local schema = table.pack(...) :: any
	local list = {} :: { SchemaNode }
	for i = 1, schema.n do
		table.insert(list, schema[i])
	end

	local route: RouteEntry = {
		name = name,
		func = fn,
		unreliable = unreliable == true,
		schema = list,
		returnType = nil,
	}

	self._eventsIn[name] = route

	local eventName = Rename(unreliable and "UE" or "E", name)
	if unreliable then
		local remote = GetUnreliableRemoteEvent(self._folder, eventName)
		remote.OnServerEvent:Connect(function(player: Player, payload: any, ...: any)
			local data = tostring(payload)
			local extrasList = table.pack(...)
			local extras = table.create(extrasList.n)

			for i = 1, extrasList.n do
				extras[i] = extrasList[i]
			end

			local reader = NetcodeBufferReader.new(data, extras)

			local decoded = table.create(#list)
			for i = 1, #list do
				decoded[i] = NetcodeUtils.readBySchemaNode(reader, list[i])
			end

			self._eventsIn[name].func(player, table.unpack(decoded, 1, #decoded))
		end)
	else
		local remote = GetRemoteEvent(self._folder, eventName)
		remote.OnServerEvent:Connect(function(player: Player, payload: any, ...: any)
			local data = tostring(payload)
			local extrasList = table.pack(...)
			local extras = table.create(extrasList.n)

			for i = 1, extrasList.n do
				extras[i] = extrasList[i]
			end

			local reader = NetcodeBufferReader.new(data, extras)

			local decoded = table.create(#list)
			for i = 1, #list do
				decoded[i] = NetcodeUtils.readBySchemaNode(reader, list[i])
			end

			self._eventsIn[name].func(player, table.unpack(decoded, 1, #decoded))
		end)
	end
end

function NetcodeServer.addFunction(
	self: NetcodeServer,
	name: string,
	fn: (...any) -> any,
	returnType: SchemaNode,
	...: SchemaNode
)
	local schema = table.pack(...) :: any
	local list = {} :: { SchemaNode }
	for i = 1, schema.n do
		table.insert(list, schema[i])
	end

	local route: RouteEntry = {
		name = name,
		func = fn,
		unreliable = false,
		schema = list,
		returnType = returnType,
	}
	self._funcsIn[name] = route

	local fnName = Rename("F", name)
	local remote = GetRemoteFunction(self._folder, fnName)

	remote.OnServerInvoke = function(player: Player, payload: any, ...: any)
		local data = tostring(payload)
		local extrasList = table.pack(...)
		local extras = table.create(extrasList.n)

		for i = 1, extrasList.n do
			extras[i] = extrasList[i]
		end

		local reader = NetcodeBufferReader.new(data, extras)

		local decoded = table.create(#list)
		for i = 1, #list do
			decoded[i] = NetcodeUtils.readBySchemaNode(reader, list[i])
		end

		local result = self._funcsIn[name].func(player, table.unpack(decoded, 1, #decoded))

		local writer = NetcodeBufferWriter.new()
		NetcodeUtils.writeBySchemaNode(writer, returnType, result)

		local retPayload, retExtras = writer:toString(), writer:getExtras()
		return retPayload, table.unpack(retExtras, 1, retExtras.n)
	end
end

local function getEventRemote(self: NetcodeServer, route: RouteEntry): RemoteEvent | UnreliableRemoteEvent
	local evName = Rename(route.unreliable and "UE" or "E", route.name)
	if route.unreliable then
		return GetUnreliableRemoteEvent(self._folder, evName)
	else
		return GetRemoteEvent(self._folder, evName)
	end
end

function NetcodeServer.callEventForPlayer(self: NetcodeServer, name: string, player: Player, ...: any)
	local route = self._eventsOut[name]
	assert(route ~= nil, "Unknown outbound event: " .. name)

	local payload, extras = PackArgs(route.schema, ...)
	local remote = getEventRemote(self, route)

	remote:FireClient(player, payload, table.unpack(extras, 1, #extras))
end

function NetcodeServer.callEventForPlayers(self: NetcodeServer, name: string, players: { Player }, ...: any)
	local route = self._eventsOut[name]
	assert(route ~= nil, "Unknown outbound event: " .. name)

	local payload, extras = PackArgs(route.schema, ...)
	local remote = getEventRemote(self, route)

	for _, player in ipairs(players) do
		remote:FireClient(player, payload, table.unpack(extras, 1, #extras))
	end
end

function NetcodeServer.callEventForAll(self: NetcodeServer, name: string, ...: any)
	local route = self._eventsOut[name]
	assert(route ~= nil, "Unknown outbound event: " .. name)

	local payload, extras = PackArgs(route.schema, ...)
	local remote = getEventRemote(self, route)

	remote:FireAllClients(payload, table.unpack(extras, 1, #extras))
end

function NetcodeServer.callEventForAllExcept(self: NetcodeServer, name: string, excludedPlayer: Player, ...: any)
	local route = self._eventsOut[name]
	assert(route ~= nil, "Unknown outbound event: " .. name)

	local payload, extras = PackArgs(route.schema, ...)
	local remote = getEventRemote(self, route)

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= excludedPlayer then
			remote:FireClient(player, payload, table.unpack(extras, 1, #extras))
		end
	end
end

function NetcodeServer.callEventForAllExceptAll(
	self: NetcodeServer,
	name: string,
	excludedPlayers: { Player },
	...: any
)
	local route = self._eventsOut[name]
	assert(route ~= nil, "Unknown outbound event: " .. name)

	local payload, extras = PackArgs(route.schema, ...)
	local remote = getEventRemote(self, route)

	for _, player in ipairs(Players:GetPlayers()) do
		if not table.find(excludedPlayers, player) then
			remote:FireClient(player, payload, table.unpack(extras, 1, #extras))
		end
	end
end

function NetcodeServer.callFunction(self: NetcodeServer, name: string, player: Player, ...: any): any
	local route = self._funcsOut[name]
	assert(route ~= nil, "Unknown outbound function: " .. name)

	local fnName = Rename("F", route.name)
	local remote = GetRemoteFunction(self._folder, fnName)
	local payload, extras = PackArgs(route.schema, ...)

	local ret = table.pack(remote:InvokeClient(player, payload, table.unpack(extras, 1, #extras)))

	if route.returnType == nil then
		return ret[1]
	end

	local retPayload = tostring(ret[1])
	local retExtras = {}
	for i = 2, ret.n do
		retExtras[i - 1] = ret[i]
	end

	local reader = NetcodeBufferReader.new(retPayload, retExtras)
	return NetcodeUtils.readBySchemaNode(reader, route.returnType)
end

function NetcodeServer:describe()
	return {
		events = (function()
			local out = {}
			for name, r in pairs(self._eventsIn) do
				out[name] = { unreliable = r.unreliable, schema = r.schema }
			end
			return out
		end)(),
		funcs = (function()
			local out = {}
			for name, r in pairs(self._funcsIn) do
				out[name] = { schema = r.schema, returnType = r.returnType }
			end
			return out
		end)(),
	}
end

return NetcodeServer
