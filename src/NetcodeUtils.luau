--!optimize 2

local NetcodeBufferReader = require(script.Parent.NetcodeBufferReader)
local NetcodeBufferWriter = require(script.Parent.NetcodeBufferWriter)
local NetcodeTypes = require(script.Parent.NetcodeTypes)

type TypeDescriptor = NetcodeTypes.TypeDescriptor
type SchemaNode = NetcodeTypes.SchemaNode

local NetcodeUtils = {}
NetcodeUtils.__index = NetcodeUtils

local ArgType = NetcodeTypes.ArgType

-- descriptor helpers ----------------------------------------------------------

local function isArrayDescriptor(desc: TypeDescriptor): boolean
	return NetcodeTypes.IsArray(desc)
end

local function isNullableDescriptor(desc: TypeDescriptor): boolean
	return NetcodeTypes.IsNullable(desc)
end

local function baseTypeOf(desc: TypeDescriptor): number
	return NetcodeTypes.BaseType(desc)
end

local function elemOf(desc: TypeDescriptor): TypeDescriptor?
	return NetcodeTypes.Elem(desc)
end

function NetcodeUtils.assertValidSchemaNode(node: SchemaNode)
	local t = typeof(node)
	if t == "number" then
		assert(NetcodeTypes.IsValidSchema(node :: any), "Invalid schema base type")
	elseif t == "table" then
		if (node :: any).id ~= nil then
			assert(NetcodeTypes.IsValidSchema(node :: any), "Invalid array descriptor")
		else
			for _, v in pairs(node :: any) do
				NetcodeUtils.assertValidSchemaNode(v)
			end
		end
	else
		error("Invalid schema node type: " .. t)
	end
end

local function writeBaseById(writer: NetcodeBufferWriter.Writer, typeId: number, value: any)
	if typeId == ArgType.NumberS8 then
		writer:writeS8(value)
	elseif typeId == ArgType.NumberS16 then
		writer:writeS16(value)
	elseif typeId == ArgType.NumberS24 then
		writer:writeS24(value)
	elseif typeId == ArgType.NumberS32 then
		writer:writeS32(value)
	elseif typeId == ArgType.NumberU4 then
		writer:writeU4(value)
	elseif typeId == ArgType.NumberU8 then
		writer:writeU8(value)
	elseif typeId == ArgType.NumberU16 then
		writer:writeU16(value)
	elseif typeId == ArgType.NumberU24 then
		writer:writeU24(value)
	elseif typeId == ArgType.NumberU32 then
		writer:writeU32(value)
	elseif typeId == ArgType.NumberF16 then
		writer:writeF16(value)
	elseif typeId == ArgType.NumberF24 then
		writer:writeF24(value)
	elseif typeId == ArgType.NumberF32 then
		writer:writeF32(value)
	elseif typeId == ArgType.NumberF64 then
		writer:writeF64(value)
	elseif typeId == ArgType.String then
		writer:writeString(value)
	elseif typeId == ArgType.Buffer then
		writer:writeBuffer(value)
	elseif typeId == ArgType.Any then
		writer:writeAny(value)
	elseif typeId == ArgType.Boolean1 then
		writer:writeBoolean1(value)
	elseif typeId == ArgType.Boolean8 then
		writer:writeBoolean8(value)
	elseif typeId == ArgType.NumberRange then
		writer:writeNumberRange(value)
	elseif typeId == ArgType.BrickColor then
		writer:writeBrickColor(value)
	elseif typeId == ArgType.Color3 then
		writer:writeColor3(value)
	elseif typeId == ArgType.UDim then
		writer:writeUDim(value)
	elseif typeId == ArgType.UDim2 then
		writer:writeUDim2(value)
	elseif typeId == ArgType.Rect then
		writer:writeRect(value)
	elseif typeId == ArgType.Vector2S16 then
		writer:writeVector2S16(value)
	elseif typeId == ArgType.Vector2F24 then
		writer:writeVector2F24(value)
	elseif typeId == ArgType.Vector2F32 then
		writer:writeVector2F32(value)
	elseif typeId == ArgType.Vector3S16 then
		writer:writeVector3S16(value)
	elseif typeId == ArgType.Vector3F24 then
		writer:writeVector3F24(value)
	elseif typeId == ArgType.Vector3F32 then
		writer:writeVector3F32(value)
	elseif typeId == ArgType.CFrameF24U8 then
		writer:writeCFrameF24U8(value)
	elseif typeId == ArgType.CFrameF32U8 then
		writer:writeCFrameF32U8(value)
	elseif typeId == ArgType.CFrameF32U16 then
		writer:writeCFrameF32U16(value)
	elseif typeId == ArgType.Region3 then
		writer:writeRegion3(value)
	elseif typeId == ArgType.NumberSequence then
		writer:writeNumberSequence(value)
	elseif typeId == ArgType.ColorSequence then
		writer:writeColorSequence(value)
	else
		error("Unknown ArgType id: " .. tostring(typeId))
	end
end

function NetcodeUtils.writeBySchemaNode(writer: NetcodeBufferWriter.Writer, schema: SchemaNode, value: any)
	if typeof(schema) == "number" then
		local descriptor = schema :: number
		if isNullableDescriptor(descriptor) then
			local present = value ~= nil
			writer:writeBoolean1(present)
			if not present then
				return
			end
		end

		local typeId = baseTypeOf(descriptor)
		writeBaseById(writer, typeId, value)
	else
		local s = schema :: any
		if s.id ~= nil then
			local nullable = isNullableDescriptor(s.id)
			if nullable then
				local present = value ~= nil
				writer:writeBoolean1(present)
				if not present then
					return
				end
			end

			local elem = elemOf(s)
			assert(elem ~= nil, "Array descriptor missing elem")

			local arr = value :: { any }
			writer:writeULEB128(#arr)
			for i = 1, #arr do
				NetcodeUtils.writeBySchemaNode(writer, elem :: SchemaNode, arr[i])
			end
		else
			local keys = {} :: { string }
			for k in pairs(s) do
				table.insert(keys, k)
			end
			table.sort(keys)
			for i = 1, #keys do
				local k = keys[i]
				NetcodeUtils.writeBySchemaNode(writer, s[k], value and value[k])
			end
		end
	end
end

function NetcodeUtils.packArgs(schema: { SchemaNode }, ...: any): (string, { [number]: any, n: number })
	local writer = NetcodeBufferWriter.new()
	local args = table.pack(...)
	for i = 1, #schema do
		local node = schema[i]
		NetcodeUtils.assertValidSchemaNode(node)
		NetcodeUtils.writeBySchemaNode(writer, node, args[i])
	end
	return writer:toString(), writer:getExtras()
end

local function readBaseById(reader: NetcodeBufferReader.Reader, typeId: number): any
	if typeId == ArgType.NumberS8 then
		return reader:readS8()
	elseif typeId == ArgType.NumberS16 then
		return reader:readS16()
	elseif typeId == ArgType.NumberS24 then
		return reader:readS24()
	elseif typeId == ArgType.NumberS32 then
		return reader:readS32()
	elseif typeId == ArgType.NumberU4 then
		return reader:readU4()
	elseif typeId == ArgType.NumberU8 then
		return reader:readU8()
	elseif typeId == ArgType.NumberU16 then
		return reader:readU16()
	elseif typeId == ArgType.NumberU24 then
		return reader:readU24()
	elseif typeId == ArgType.NumberU32 then
		return reader:readU32()
	elseif typeId == ArgType.NumberF16 then
		return reader:readF16()
	elseif typeId == ArgType.NumberF24 then
		return reader:readF24()
	elseif typeId == ArgType.NumberF32 then
		return reader:readF32()
	elseif typeId == ArgType.NumberF64 then
		return reader:readF64()
	elseif typeId == ArgType.String then
		return reader:readString()
	elseif typeId == ArgType.Buffer then
		return reader:readBuffer()
	elseif typeId == ArgType.Any then
		return reader:readAny()
	elseif typeId == ArgType.Boolean1 then
		return reader:readBoolean1()
	elseif typeId == ArgType.Boolean8 then
		return reader:readBoolean8()
	elseif typeId == ArgType.NumberRange then
		return reader:readNumberRange()
	elseif typeId == ArgType.BrickColor then
		return reader:readBrickColor()
	elseif typeId == ArgType.Color3 then
		return reader:readColor3()
	elseif typeId == ArgType.UDim then
		return reader:readUDim()
	elseif typeId == ArgType.UDim2 then
		return reader:readUDim2()
	elseif typeId == ArgType.Rect then
		return reader:readRect()
	elseif typeId == ArgType.Vector2S16 then
		return reader:readVector2S16()
	elseif typeId == ArgType.Vector2F24 then
		return reader:readVector2F24()
	elseif typeId == ArgType.Vector2F32 then
		return reader:readVector2F32()
	elseif typeId == ArgType.Vector3S16 then
		return reader:readVector3S16()
	elseif typeId == ArgType.Vector3F24 then
		return reader:readVector3F24()
	elseif typeId == ArgType.Vector3F32 then
		return reader:readVector3F32()
	elseif typeId == ArgType.CFrameF24U8 then
		return reader:readCFrameF24U8()
	elseif typeId == ArgType.CFrameF32U8 then
		return reader:readCFrameF32U8()
	elseif typeId == ArgType.CFrameF32U16 then
		return reader:readCFrameF32U16()
	elseif typeId == ArgType.Region3 then
		return reader:readRegion3()
	elseif typeId == ArgType.NumberSequence then
		return reader:readNumberSequence()
	elseif typeId == ArgType.ColorSequence then
		return reader:readColorSequence()
	else
		error("Unknown ArgType id: " .. tostring(typeId))
	end
end

function NetcodeUtils.readBySchemaNode(reader: NetcodeBufferReader.Reader, schema: SchemaNode): any
	if typeof(schema) == "number" then
		local descriptor = schema :: number
		if isNullableDescriptor(descriptor) then
			local present = reader:readBoolean1()
			if not present then
				return nil
			end
		end
		local typeId = baseTypeOf(descriptor)
		return readBaseById(reader, typeId)
	else
		local s = schema :: any
		if s.id ~= nil then
			local nullable = isNullableDescriptor(s.id)
			if nullable then
				local present = reader:readBoolean1()
				if not present then
					return nil
				end
			end

			local elem = elemOf(s)
			assert(elem ~= nil, "Array descriptor missing elem")

			local n = reader:readULEB128()
			local out = table.create(n)
			for i = 1, n do
				out[i] = NetcodeUtils.readBySchemaNode(reader, elem :: SchemaNode)
			end
			return out
		else
			local keys = {} :: { string }
			for k in pairs(s) do
				table.insert(keys, k)
			end
			table.sort(keys)

			local obj = {}
			for i = 1, #keys do
				local k = keys[i]
				obj[k] = NetcodeUtils.readBySchemaNode(reader, s[k])
			end
			return obj
		end
	end
end

return NetcodeUtils
