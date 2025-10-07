--!strict
--!optimize 2

local NetcodeTypes = {}
NetcodeTypes.__index = NetcodeTypes

NetcodeTypes.NullMask = 0x80 -- 128
NetcodeTypes.ArrayMask = 0x40 -- 64
NetcodeTypes.TypeMask = 0x3F -- 63

local CurrentMaxArgType = 36 -- The value of the last element in the ArgType table

NetcodeTypes.ArgType = table.freeze({
	NumberS8 = 1,
	NumberS16 = 2,
	NumberS24 = 3,
	NumberS32 = 4,

	NumberU4 = 5,
	NumberU8 = 6,
	NumberU16 = 7,
	NumberU24 = 8,
	NumberU32 = 9,

	NumberF16 = 10,
	NumberF24 = 11,
	NumberF32 = 12,
	NumberF64 = 13,

	String = 14,

	Buffer = 15,

	Any = 16,

	Boolean1 = 17,
	Boolean8 = 18,

	NumberRange = 19,
	BrickColor = 20,
	Color3 = 21,
	UDim = 22,
	UDim2 = 23,
	Rect = 24,

	Vector2S16 = 25,
	Vector2F24 = 26,
	Vector2F32 = 27,

	Vector3S16 = 28,
	Vector3F24 = 29,
	Vector3F32 = 30,

	CFrameF24U8 = 31,
	CFrameF32U8 = 32,
	CFrameF32U16 = 33,

	Region3 = 34,
	NumberSequence = 35,
	ColorSequence = 36,
})

export type TypeDescriptor = number | { id: number, elem: TypeDescriptor }
export type SchemaNode = TypeDescriptor | { [string]: SchemaNode }

local function IsArrayHeader(header: number): boolean
	return bit32.band(header, NetcodeTypes.ArrayMask) ~= 0
end

local function IsNullableHeader(header: number): boolean
	return bit32.band(header, NetcodeTypes.NullMask) ~= 0
end

local function BaseType(header: number): number
	return bit32.band(header, NetcodeTypes.TypeMask)
end

local function MakeHeader(baseType: number, isNullable: boolean, isArray: boolean): number
	if isArray then
		assert(baseType >= 0 and baseType <= NetcodeTypes.TypeMask, "Invalid array base type (0..63)")
	else
		assert(baseType >= 1 and baseType <= NetcodeTypes.TypeMask, "Invalid base type (1..63)")
	end

	local header = baseType

	if isNullable then
		header = bit32.bor(header, NetcodeTypes.NullMask)
	end

	if isArray then
		header = bit32.bor(header, NetcodeTypes.ArrayMask)
	end

	return header
end

function NetcodeTypes.Base(typeId: number, nullable: boolean?): number
	return MakeHeader(typeId, nullable == true, false)
end

function NetcodeTypes.Nullable(descriptor: TypeDescriptor): TypeDescriptor
	if type(descriptor) == "number" then
		return bit32.bor(descriptor, NetcodeTypes.NullMask)
	else
		return { id = bit32.bor(descriptor.id, NetcodeTypes.NullMask), elem = descriptor.elem }
	end
end

function NetcodeTypes.AsNonNullable(descriptor: TypeDescriptor): TypeDescriptor
	if type(descriptor) == "number" then
		return bit32.band(descriptor, bit32.bnot(NetcodeTypes.NullMask))
	else
		return { id = bit32.band(descriptor.id, bit32.bnot(NetcodeTypes.NullMask)), elem = descriptor.elem }
	end
end

function NetcodeTypes.Array(elem: SchemaNode): SchemaNode
	local elemDesc: SchemaNode = elem
	if type(elemDesc) == "number" then
		elemDesc = MakeHeader(elemDesc, false, false)
	end

	return { id = MakeHeader(0, false, true), elem = elemDesc :: TypeDescriptor }
end

function NetcodeTypes.IsArray(descriptor: TypeDescriptor): boolean
	local header

	if type(descriptor) == "number" then
		header = descriptor
	else
		header = descriptor.id
	end

	return IsArrayHeader(header)
end

function NetcodeTypes.IsNullable(descriptor: TypeDescriptor): boolean
	local header

	if type(descriptor) == "number" then
		header = descriptor
	else
		header = descriptor.id
	end

	return IsNullableHeader(header)
end

function NetcodeTypes.BaseType(descriptor: TypeDescriptor): number
	local header

	if type(descriptor) == "number" then
		header = descriptor
	else
		header = descriptor.id
	end

	return BaseType(header)
end

function NetcodeTypes.Elem(descriptor: TypeDescriptor): TypeDescriptor?
	if type(descriptor) == "table" and IsArrayHeader(descriptor.id) then
		return descriptor.elem
	end

	return nil
end

function NetcodeTypes.IsValidTypeDescriptor(descriptor: TypeDescriptor): boolean
	if type(descriptor) == "number" then
		if IsArrayHeader(descriptor) then
			return false
		end

		local base = BaseType(descriptor)
		return base >= 1 and base <= CurrentMaxArgType
	end

	if not IsArrayHeader(descriptor.id) then
		return false
	end

	local elem = descriptor.elem
	if type(elem) == "number" then
		return NetcodeTypes.IsValidTypeDescriptor(elem)
	elseif type(elem) == "table" then
		if (elem :: any).id ~= nil then
			return NetcodeTypes.IsValidTypeDescriptor(elem :: TypeDescriptor)
		else
			return NetcodeTypes.IsValidSchema(elem :: { [string]: SchemaNode })
		end
	end

	return false
end

function NetcodeTypes.IsObjectSchema(table: any): boolean
	return type(table) == "table" and (table :: any).id == nil
end

function NetcodeTypes.IsValidSchema(node: SchemaNode): boolean
	if type(node) == "number" or (type(node) == "table" and (node :: any).id ~= nil) then
		return NetcodeTypes.IsValidTypeDescriptor(node :: TypeDescriptor)
	end

	for k, v in pairs(node :: { [string]: SchemaNode }) do
		if type(k) ~= "string" then
			return false
		end

		if not NetcodeTypes.IsValidSchema(v) then
			return false
		end
	end

	return true
end

function NetcodeTypes.Normalize(node: any): SchemaNode
	if type(node) == "number" then
		return MakeHeader(node, false, false)
	end

	if type(node) == "table" then
		if (node :: any).id ~= nil then
			return node :: TypeDescriptor
		end

		local out: { [string]: SchemaNode } = {}
		for k, v in pairs(node :: { [string]: any }) do
			out[k] = NetcodeTypes.Normalize(v)
		end

		return out
	end

	error("Unsupported schema node type: " .. typeof(node))
end

return table.freeze(NetcodeTypes)
