local NetcodeClient = require(script.NetcodeClient)
local NetcodeServer = require(script.NetcodeServer)
local NetcodeTypes = require(script.NetcodeTypes)

export type Client = NetcodeClient.NetcodeClient
export type Server = NetcodeServer.NetcodeServer

local library = {
	client = NetcodeClient,
	server = NetcodeServer,
}

local types = table.clone(NetcodeTypes.ArgType)

types.Array = NetcodeTypes.Array
types.Nullable = NetcodeTypes.Nullable

library.types = types

table.freeze(library.types)
table.freeze(library)

return library
