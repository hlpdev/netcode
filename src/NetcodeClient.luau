--!optimize 2

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RootName = "Netcode"

local NetcodeBufferReader = require(script.Parent.NetcodeBufferReader)
local NetcodeBufferWriter = require(script.Parent.NetcodeBufferWriter)
local NetcodeTypes = require(script.Parent.NetcodeTypes)
local NetcodeUtils = require(script.Parent.NetcodeUtils)

type SchemaNode = NetcodeTypes.SchemaNode

local NetcodeClient = {}
NetcodeClient.__index = NetcodeClient

export type RouteEntry = {
	name: string,
	func: (...any) -> any,
	unreliable: boolean,
	schema: { SchemaNode },
	returnType: SchemaNode?,
}

export type NetcodeClient = {
	_tag: string,
	_isClient: boolean,
	_folder: Folder,

	_eventsIn: { [string]: RouteEntry },
	_funcsIn: { [string]: RouteEntry },
	_eventsOut: { [string]: RouteEntry },
	_funcsOut: { [string]: RouteEntry },

	addEvent: (self: NetcodeClient, name: string, fn: (...any) -> (), unreliable: boolean, ...SchemaNode) -> (),

	addFunction: (
		self: NetcodeClient,
		name: string,
		fn: (...any) -> any,
		returnType: SchemaNode,
		...SchemaNode
	) -> (),

	callEvent: (self: NetcodeClient, name: string, ...any) -> (),
	callFunction: (self: NetcodeClient, name: string, ...any) -> any,

	describe: (
		self: NetcodeClient
	) -> {
		events: { [string]: { unreliable: boolean, schema: { SchemaNode } } },
		funcs: { [string]: { schema: { SchemaNode }, returnType: SchemaNode } },
	},
}

local function RootFolder(): Folder
	local root = ReplicatedStorage:FindFirstChild(RootName) :: Folder?
	assert(root ~= nil, "Netcode root folder does not exist. Server must create it first.")
	return root :: Folder
end

local function TagFolder(tag: string): Folder
	local root = RootFolder()
	local tagFolder = root:FindFirstChild(tag) :: Folder?
	assert(tagFolder ~= nil, "Netcode tag '" .. tag .. "' does not exist. Server must create it first.")
	return tagFolder :: Folder
end

local function Rename(prefix: string, name: string): string
	return prefix .. "_" .. name
end

local function GetRemoteEvent(folder: Folder, name: string): RemoteEvent
	local remote = folder:FindFirstChild(name) :: RemoteEvent?
	assert(remote ~= nil, "RemoteEvent '" .. name .. "' missing for this Netcode tag.")
	return remote :: RemoteEvent
end

local function GetUnreliableRemoteEvent(folder: Folder, name: string): UnreliableRemoteEvent
	local remote = folder:FindFirstChild(name) :: UnreliableRemoteEvent?
	assert(remote ~= nil, "UnreliableRemoteEvent '" .. name .. "' missing for this Netcode tag.")
	return remote :: UnreliableRemoteEvent
end

local function GetRemoteFunction(folder: Folder, name: string): RemoteFunction
	local remote = folder:FindFirstChild(name) :: RemoteFunction?
	assert(remote ~= nil, "RemoteFunction '" .. name .. "' missing for this Netcode tag.")
	return remote :: RemoteFunction
end

local function GetControlFunction(folder: Folder): RemoteFunction
	local name = Rename("SYS", "Control")
	local remote = folder:FindFirstChild(name) :: RemoteFunction?
	assert(remote ~= nil, "Control RemoteFunction '" .. name .. "' missing. NetcodeServer must be created first.")
	return remote
end

function NetcodeClient.new(tag: string): NetcodeClient
	assert(RunService:IsClient(), "NetcodeClient can only be used on the client.")

	local self = setmetatable({
		_tag = tag,
		_isClient = true,
		_folder = TagFolder(tag),

		_eventsIn = {},
		_eventsOut = {},
		_funcsIn = {},
		_funcsOut = {},
	}, NetcodeClient)

	return self
end

local function Control(self: NetcodeClient): RemoteFunction
	return GetControlFunction(self._folder)
end

local function GetEventRemote(self: NetcodeClient, route: RouteEntry): RemoteEvent | UnreliableRemoteEvent
	local evName = Rename(route.unreliable and "UE" or "E", route.name)
	if route.unreliable then
		return GetUnreliableRemoteEvent(self._folder, evName)
	else
		return GetRemoteEvent(self._folder, evName)
	end
end

local function EnsureOutboundEvent(self: NetcodeClient, name: string): RouteEntry
	local route = self._eventsOut[name]
	if route ~= nil then
		return route
	end

	local rf = Control(self)
	local info = rf:InvokeServer({ op = "getInboundEvent", name = name })
	assert(info ~= nil, "Unknown inbound event on server: " .. name)

	local unreliable = info.unreliable == true
	local schema = info.schema :: { SchemaNode }

	for i = 1, #schema do
		NetcodeUtils.assertValidSchemaNode(schema[i])
	end

	route = {
		name = name,
		func = function() end,
		unreliable = unreliable,
		schema = schema,
		returnType = nil,
	}

	self._eventsOut[name] = route
	return route
end

local function EnsureOutboundFunction(self: NetcodeClient, name: string): RouteEntry
	local route = self._funcsOut[name]
	if route ~= nil then
		return route
	end

	local rf = Control(self)
	local info = rf:InvokeServer({ op = "getInboundFunction", name = name })
	assert(info ~= nil, "Unknown inbound function on server: " .. name)

	local schema = info.schema :: { SchemaNode }
	local returnType = info.returnType :: SchemaNode

	for i = 1, #schema do
		NetcodeUtils.assertValidSchemaNode(schema[i])
	end
	if returnType ~= nil then
		NetcodeUtils.assertValidSchemaNode(returnType)
	end

	route = {
		name = name,
		func = function()
			return nil
		end,
		unreliable = false,
		schema = schema,
		returnType = returnType,
	}

	self._funcsOut[name] = route
	return route
end

function NetcodeClient.describe(self: NetcodeClient)
	local rf = Control(self)
	return rf:InvokeServer({ op = "describe" })
end

local function RegisterEventOnServer(self: NetcodeClient, name: string, unreliable: boolean, schema: { SchemaNode })
	local rf = Control(self)
	return rf:InvokeServer({
		op = "registerEvent",
		name = name,
		unreliable = unreliable,
		schema = schema,
	})
end

local function RegisterFunctionOnServer(
	self: NetcodeClient,
	name: string,
	schema: { SchemaNode },
	returnType: SchemaNode
)
	local rf = Control(self)
	return rf:InvokeServer({
		op = "registerFunction",
		name = name,
		schema = schema,
		returnType = returnType,
	})
end

function NetcodeClient.addEvent(
	self: NetcodeClient,
	name: string,
	fn: (...any) -> (),
	unreliable: boolean,
	...: SchemaNode
)
	local schemaPack = table.pack(...) :: any
	local list = {} :: { SchemaNode }
	for i = 1, schemaPack.n do
		table.insert(list, schemaPack[i])
	end

	for i = 1, #list do
		NetcodeUtils.assertValidSchemaNode(list[i])
	end

	local route: RouteEntry = {
		name = name,
		func = fn,
		unreliable = unreliable == true,
		schema = list,
		returnType = nil,
	}
	self._eventsIn[name] = route

	RegisterEventOnServer(self, name, unreliable == true, list)

	local eventName = Rename(unreliable and "UE" or "E", name)
	if unreliable then
		local remote = GetUnreliableRemoteEvent(self._folder, eventName)
		remote.OnClientEvent:Connect(function(payload: any, ...: any)
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

			self._eventsIn[name].func(table.unpack(decoded, 1, #decoded))
		end)
	else
		local remote = GetRemoteEvent(self._folder, eventName)
		remote.OnClientEvent:Connect(function(payload: any, ...: any)
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

			self._eventsIn[name].func(table.unpack(decoded, 1, #decoded))
		end)
	end
end

function NetcodeClient.addFunction(
	self: NetcodeClient,
	name: string,
	fn: (...any) -> any,
	returnType: SchemaNode,
	...: SchemaNode
)
	local schemaPack = table.pack(...) :: any
	local list = {} :: { SchemaNode }
	for i = 1, schemaPack.n do
		table.insert(list, schemaPack[i])
	end

	NetcodeUtils.assertValidSchemaNode(returnType)
	for i = 1, #list do
		NetcodeUtils.assertValidSchemaNode(list[i])
	end

	local route: RouteEntry = {
		name = name,
		func = fn,
		unreliable = false,
		schema = list,
		returnType = returnType,
	}
	self._funcsIn[name] = route

	RegisterFunctionOnServer(self, name, list, returnType)

	local fnName = Rename("F", name)
	local remote = GetRemoteFunction(self._folder, fnName)

	remote.OnClientInvoke = function(payload: any, ...: any)
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

		local result = self._funcsIn[name].func(table.unpack(decoded, 1, #decoded))

		local writer = NetcodeBufferWriter.new()
		NetcodeUtils.writeBySchemaNode(writer, returnType, result)

		local retPayload, retExtras = writer:toString(), writer:getExtras()

		return retPayload, table.unpack(retExtras, 1, #retExtras)
	end
end

function NetcodeClient.callEvent(self: NetcodeClient, name: string, ...: any)
	local route = EnsureOutboundEvent(self, name)

	local payload, extras = NetcodeUtils.packArgs(route.schema, ...)
	local remote = GetEventRemote(self, route)
	remote:FireServer(payload, table.unpack(extras, 1, extras.n))
end

function NetcodeClient.callFunction(self: NetcodeClient, name: string, ...: any): any
	local route = EnsureOutboundFunction(self, name)

	local fnName = Rename("F", route.name)
	local remote = GetRemoteFunction(self._folder, fnName)

	local payload, extras = NetcodeUtils.packArgs(route.schema, ...)
	local ret = table.pack(remote:InvokeServer(payload, table.unpack(extras, 1, #extras)))

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

return NetcodeClient
