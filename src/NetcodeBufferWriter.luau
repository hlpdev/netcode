--!optimize 2

local NetcodeTypes = require(script.Parent.NetcodeTypes)

type TypeDescriptor = NetcodeTypes.TypeDescriptor
type SchemaNode = NetcodeTypes.SchemaNode

local Writer = {}
Writer.__index = Writer

export type Writer = {
	_bytes: { number },
	_bitBuffer: number,
	_bitCount: number,
	_extras: { [number]: any, n: number },

	new: () -> Writer,

	writeBits: (self: Writer, value: number, bitCount: number) -> (),
	alignByte: (self: Writer) -> (),

	writeS8: (self: Writer, value: number) -> (),
	writeS16: (self: Writer, value: number) -> (),
	writeS24: (self: Writer, value: number) -> (),
	writeS32: (self: Writer, value: number) -> (),

	writeU4: (self: Writer, value: number) -> (),
	writeU8: (self: Writer, value: number) -> (),
	writeU16: (self: Writer, value: number) -> (),
	writeU24: (self: Writer, value: number) -> (),
	writeU32: (self: Writer, value: number) -> (),

	writeF16: (self: Writer, value: number) -> (),
	writeF24: (self: Writer, value: number) -> (),
	writeF32: (self: Writer, value: number) -> (),
	writeF64: (self: Writer, value: number) -> (),

	writeString: (self: Writer, value: string) -> (),

	writeBuffer: (self: Writer, value: buffer) -> (),

	writeAny: (self: Writer, value: any) -> (),

	writeBoolean1: (self: Writer, value: boolean) -> (),
	writeBoolean8: (self: Writer, value: boolean) -> (),

	writeNumberRange: (self: Writer, value: NumberRange) -> (),
	writeBrickColor: (self: Writer, value: BrickColor) -> (),
	writeColor3: (self: Writer, value: Color3) -> (),
	writeUDim: (self: Writer, value: UDim) -> (),
	writeUDim2: (self: Writer, value: UDim2) -> (),
	writeRect: (self: Writer, value: Rect) -> (),

	writeVector2S16: (self: Writer, value: Vector2) -> (),
	writeVector2F24: (self: Writer, value: Vector2) -> (),
	writeVector2F32: (self: Writer, value: Vector2) -> (),

	writeVector3S16: (self: Writer, value: Vector3) -> (),
	writeVector3F24: (self: Writer, value: Vector3) -> (),
	writeVector3F32: (self: Writer, value: Vector3) -> (),

	writeCFrameF24U8: (self: Writer, value: CFrame) -> (),
	writeCFrameF32U8: (self: Writer, value: CFrame) -> (),
	writeCFrameF32U16: (self: Writer, value: CFrame) -> (),

	writeRegion3: (self: Writer, value: Region3) -> (),
	writeNumberSequence: (self: Writer, value: NumberSequence) -> (),
	writeColorSequence: (self: Writer, value: ColorSequence) -> (),

	writeULEB128: (self: Writer, value: number) -> (),

	getExtras: (self: Writer) -> { [number]: any, n: number },

	toString: (self: Writer) -> string,
}

function Writer.new(): Writer
	local self = setmetatable({
		_bytes = {} :: { number },
		_bitBuffer = 0,
		_bitCount = 0,
		_extras = { n = 0 } :: { [number]: any, n: number },
	}, Writer)

	return self
end

function Writer.writeBits(self: Writer, value: number, bitCount: number)
	local mask = bit32.lshift(1, bitCount) - 1
	local v = bit32.band(value, mask)

	self._bitBuffer = bit32.bor(self._bitBuffer, bit32.lshift(v, self._bitCount))
	self._bitCount += bitCount

	while self._bitCount >= 8 do
		local byte = bit32.band(self._bitBuffer, 0xFF)
		table.insert(self._bytes, byte)
		self._bitBuffer = bit32.rshift(self._bitBuffer, 8)
		self._bitCount -= 8
	end
end

function Writer.alignByte(self: Writer)
	if self._bitCount > 0 then
		table.insert(self._bytes, bit32.band(self._bitBuffer, 0xFF))
		self._bitBuffer = 0
		self._bitCount = 0
	end
end

local function writeUBytes(self: Writer, value: number, count: number)
	self:alignByte()
	for _ = 1, count do
		table.insert(self._bytes, bit32.band(value, 0xFF))
		value = bit32.rshift(value, 8)
	end
end

local function toTwos(value: number, bits: number): number
	local max = bit32.lshift(1, bits)
	if value < 0 then
		value += max
	end
	return bit32.band(value, max - 1)
end

function Writer.writeU4(self: Writer, value: number)
	self:writeBits(value, 4)
end

function Writer.writeU8(self: Writer, value: number)
	writeUBytes(self, value, 1)
end

function Writer.writeU16(self: Writer, value: number)
	writeUBytes(self, value, 2)
end

function Writer.writeU24(self: Writer, value: number)
	writeUBytes(self, value, 3)
end

function Writer.writeU32(self: Writer, value: number)
	writeUBytes(self, value, 4)
end

function Writer.writeS8(self: Writer, value: number)
	self:writeU8(toTwos(value, 8))
end

function Writer.writeS16(self: Writer, value: number)
	self:writeU16(toTwos(value, 16))
end

function Writer.writeS24(self: Writer, value: number)
	self:writeU24(toTwos(value, 24))
end

function Writer.writeS32(self: Writer, value: number)
	self:writeU32(toTwos(value, 32))
end

local function packF32LE(self: Writer, value: number)
	if value ~= value then
		self:writeU32(0x7FC00000)
		return
	end

	if value == math.huge then
		self:writeU32(0x7F800000)
		return
	end

	if value == -math.huge then
		self:writeU32(0xFF800000)
		return
	end

	local sign = 0
	if value < 0 then
		sign = 1
		value = -value
	end

	if value == 0 then
		self:writeU32(bit32.lshift(sign, 31))
		return
	end

	local frac, exp = math.frexp(value)
	exp -= 1

	local E = exp + 127

	if E <= 0 then
		local mant = math.floor(frac * (2 ^ (23 + exp)) + 0.5)
		self:writeU32(bit32.bor(bit32.lshift(sign, 31), mant))
	elseif E >= 255 then
		self:writeU32(bit32.bor(bit32.lshift(sign, 31), bit32.lshift(0xFF, 23)))
	else
		local mant = math.floor((frac - 0.5) * (2 ^ 24) + 0.5) % 0x800000
		self:writeU32(bit32.bor(bit32.lshift(sign, 31), bit32.lshift(E, 23), mant))
	end
end

local function packF64LE(self: Writer, value: number)
	if value ~= value then
		self:writeU32(0)
		self:writeU32(0x7FF80000)
		return
	end

	if value == math.huge then
		self:writeU32(0)
		self:writeU32(0x7FF00000)
		return
	end

	if value == -math.huge then
		self:writeU32(0)
		self:writeU32(0xFFF00000)
		return
	end

	local sign = 0

	if value < 0 then
		sign = 1
		value = -value
	end

	if value == 0 then
		self:writeU32(0)
		self:writeU32(bit32.lshift(sign, 31))
		return
	end

	local frac, exp = math.frexp(value)
	exp -= 1

	local E = exp + 1023

	if E <= 0 then
		local mant = math.floor(frac * 2 ^ (52 + exp) + 0.5)
		local lo = mant % 0x100000000
		local hiMant = math.floor(mant / 0x100000000) % 0x100000
		self:writeU32(lo)
		self:writeU32(bit32.bor(bit32.lshift(sign, 31), hiMant))
	elseif E >= 0x7FF then
		self:writeU32(0)
		self:writeU32(bit32.bor(bit32.lshift(sign, 31), bit32.lshift(0x7FF, 20)))
	else
		local mant = math.floor((frac - 0.5) * 2 ^ 53 + 0.5)
		local lo = mant % 0x100000000
		local hiMant = math.floor(mant / 0x100000000) % 0x100000
		self:writeU32(lo)
		self:writeU32(bit32.bor(bit32.lshift(sign, 31), bit32.lshift(E, 20), hiMant))
	end
end

function Writer.writeF16(self: Writer, value: number)
	local tmp = Writer.new() :: Writer
	packF32LE(tmp, value)
	local u32 = (tmp._bytes[1] or 0)
		+ bit32.lshift((tmp._bytes[2] or 0), 8)
		+ bit32.lshift((tmp._bytes[3] or 0), 16)
		+ bit32.lshift((tmp._bytes[4] or 0), 24)

	local sign = bit32.band(bit32.rshift(u32, 31), 1)
	local E = bit32.band(bit32.rshift(u32, 23), 0xFF)
	local M = bit32.band(u32, 0x7FFFFF)

	if E == 0xFF then
		self:writeU16(bit32.bor(bit32.lshift(sign, 15), 0x7C00, (M ~= 0) and 1 or 0))
		return
	end

	if E == 0 then
		self:writeU16(bit32.lshift(sign, 15))
		return
	end

	local e16 = E - 127 + 15
	if e16 <= 0 then
		local mant = bit32.rshift(bit32.bor(M, 0x800000), (1 - e16 + 13))
		self:writeU16(bit32.bor(bit32.lshift(sign, 15), mant))
	elseif e16 >= 0x1F then
		self:writeU16(bit32.bor(bit32.lshift(sign, 15), 0x7C00))
	else
		local mant = bit32.rshift(M + 0x1000, 13)
		if mant == 0x400 then
			mant = 0
			e16 += 1
			if e16 >= 0x1F then
				self:writeU16(bit32.bor(bit32.lshift(sign, 15), 0x7C00))
				return
			end
		end
		self:writeU16(bit32.bor(bit32.lshift(sign, 15), bit32.lshift(e16, 10), bit32.band(mant, 0x3FF)))
	end
end

function Writer.writeF24(self: Writer, value: number)
	local scaled = math.floor(value * 65536 + 0.5)
	self:writeS24(scaled)
end

function Writer.writeF32(self: Writer, value: number)
	packF32LE(self, value)
end

function Writer.writeF64(self: Writer, value: number)
	packF64LE(self, value)
end

function Writer.writeULEB128(self: Writer, value: number)
	self:alignByte()
	repeat
		local b = bit32.band(value, 0x7F)
		value = bit32.rshift(value, 7)
		if value ~= 0 then
			b = bit32.bor(b, 0x80)
		end
		table.insert(self._bytes, b)
	until value == 0
end

function Writer.writeString(self: Writer, value: string)
	self:writeULEB128(#value)
	self:alignByte()
	for i = 1, #value do
		table.insert(self._bytes, string.byte(value, i))
	end
end

function Writer.writeBuffer(self: Writer, value: buffer)
	local n = buffer.len(value)
	self:writeULEB128(n)
	self:alignByte()
	for i = 0, n - 1 do
		table.insert(self._bytes, buffer.readu8(value, i))
	end
end

function Writer.writeAny(self: Writer, value: any)
	self._extras.n += 1
	self._extras[self._extras.n] = value
end

function Writer.writeBoolean1(self: Writer, value: boolean)
	self:writeBits(value and 1 or 0, 1)
end

function Writer.writeBoolean8(self: Writer, value: boolean)
	self:writeU8(value and 1 or 0)
end

function Writer.writeNumberRange(self: Writer, value: NumberRange)
	self:writeF32(value.Min)
	self:writeF32(value.Max)
end

function Writer.writeBrickColor(self: Writer, value: BrickColor)
	self:writeU16(value.Number)
end

function Writer.writeColor3(self: Writer, value: Color3)
	self:writeF32(value.R)
	self:writeF32(value.G)
	self:writeF32(value.B)
end

function Writer.writeUDim(self: Writer, value: UDim)
	self:writeF32(value.Scale)
	self:writeS16(math.floor(value.Offset))
end

function Writer.writeUDim2(self: Writer, value: UDim2)
	self:writeF32(value.X.Scale)
	self:writeS16(math.floor(value.X.Offset))
	self:writeF32(value.Y.Scale)
	self:writeS16(math.floor(value.Y.Offset))
end

function Writer.writeRect(self: Writer, value: Rect)
	self:writeF32(value.Min.X)
	self:writeF32(value.Min.Y)
	self:writeF32(value.Max.X)
	self:writeF32(value.Max.Y)
end

function Writer.writeVector2S16(self: Writer, value: Vector2)
	self:writeS16(math.floor(value.X))
	self:writeS16(math.floor(value.Y))
end

function Writer.writeVector2F24(self: Writer, value: Vector2)
	self:writeF24(value.X)
	self:writeF24(value.Y)
end

function Writer.writeVector2F32(self: Writer, value: Vector2)
	self:writeF32(value.X)
	self:writeF32(value.Y)
end

function Writer.writeVector3S16(self: Writer, value: Vector3)
	self:writeS16(math.floor(value.X))
	self:writeS16(math.floor(value.Y))
	self:writeS16(math.floor(value.Z))
end

function Writer.writeVector3F24(self: Writer, value: Vector3)
	self:writeF24(value.X)
	self:writeF24(value.Y)
	self:writeF24(value.Z)
end

function Writer.writeVector3F32(self: Writer, value: Vector3)
	self:writeF32(value.X)
	self:writeF32(value.Y)
	self:writeF32(value.Z)
end

local function CFrameToQuaternions(value: CFrame): (number, number, number, number)
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = value:GetComponents()

	local trace = r00 + r11 + r22
	local qw, qx, qy, qz

	if trace > 0 then
		local s = math.sqrt(trace + 1) * 2
		qw = 0.25 * s
		qx = (r21 - r12) / s
		qy = (r02 - r20) / s
		qz = (r10 - r01) / s
	elseif r00 > r11 and r00 > r22 then
		local s = math.sqrt(1 + r00 - r11 - r22) * 2
		qw = (r21 - r12) / s
		qx = 0.25 * s
		qy = (r01 + r10) / s
		qz = (r02 + r20) / s
	elseif r11 > r22 then
		local s = math.sqrt(1 + r11 - r00 - r22) * 2
		qw = (r02 - r20) / s
		qx = (r01 + r10) / s
		qy = 0.25 * s
		qz = (r12 + r21) / s
	else
		local s = math.sqrt(1 + r22 - r00 - r11) * 2
		qw = (r10 - r01) / s
		qx = (r02 + r20) / s
		qy = (r12 + r21) / s
		qz = 0.25 * s
	end

	local mag = math.sqrt(qw * qw + qx * qx + qy * qy + qz * qz)
	if mag > 0 then
		qw /= mag
		qx /= mag
		qy /= mag
		qz /= mag
	else
		qw = 1
		qx = 0
		qy = 0
		qz = 0
	end

	if qw < 0 then
		qw = -qw
		qx = -qx
		qy = -qy
		qz = -qz
	end

	return qx, qy, qz, qw
end

local function QuaternionsToU8(x: number, y: number, z: number, w: number): (number, number, number, number)
	local function Quaternion8(c: number): number
		local u = math.floor(((c * 0.5) + 0.5) * 255 + 0.5)

		if u < 0 then
			u = 0
		elseif u > 255 then
			u = 255
		end

		return u
	end

	return Quaternion8(x), Quaternion8(y), Quaternion8(z), Quaternion8(w)
end

local function QuaternionsToU16(x: number, y: number, z: number, w: number): (number, number, number, number)
	local function Quaternion16(c: number): number
		local u = math.floor(((c * 0.5) + 0.5) * 65535 + 0.5)

		if u < 0 then
			u = 0
		elseif u > 65535 then
			u = 65535
		end

		return u
	end

	return Quaternion16(x), Quaternion16(y), Quaternion16(z), Quaternion16(w)
end

function Writer.writeCFrameF24U8(self: Writer, value: CFrame)
	local pos = value.Position
	self:writeF24(pos.X)
	self:writeF24(pos.Y)
	self:writeF24(pos.Z)

	local qx, qy, qz, qw = CFrameToQuaternions(value)
	local ux, uy, uz, uw = QuaternionsToU8(qx, qy, qz, qw)
	self:writeU8(ux)
	self:writeU8(uy)
	self:writeU8(uz)
	self:writeU8(uw)
end

function Writer.writeCFrameF32U8(self: Writer, value: CFrame)
	local pos = value.Position
	self:writeF32(pos.X)
	self:writeF32(pos.Y)
	self:writeF32(pos.Z)

	local qx, qy, qz, qw = CFrameToQuaternions(value)
	local ux, uy, uz, uw = QuaternionsToU8(qx, qy, qz, qw)
	self:writeU8(ux)
	self:writeU8(uy)
	self:writeU8(uz)
	self:writeU8(uw)
end

function Writer.writeCFrameF32U16(self: Writer, value: CFrame)
	local pos = value.Position
	self:writeF32(pos.X)
	self:writeF32(pos.Y)
	self:writeF32(pos.Z)

	local qx, qy, qz, qw = CFrameToQuaternions(value)
	local ux, uy, uz, uw = QuaternionsToU16(qx, qy, qz, qw)
	self:writeU16(ux)
	self:writeU16(uy)
	self:writeU16(uz)
	self:writeU16(uw)
end

function Writer.writeRegion3(self: Writer, value: Region3)
	local size = value.Size
	local half = size / 2
	local center = value.CFrame.Position
	local min = center - half
	local max = center + half
	self:writeF32(min.X)
	self:writeF32(min.Y)
	self:writeF32(min.Z)
	self:writeF32(max.X)
	self:writeF32(max.Y)
	self:writeF32(max.Z)
end

function Writer.writeNumberSequence(self: Writer, value: NumberSequence)
	local keys = value.Keypoints
	self:writeULEB128(#keys)

	for i = 1, #keys do
		local keypoint = keys[i]
		self:writeF32(keypoint.Time)
		self:writeF32(keypoint.Value)
		self:writeF32(keypoint.Envelope)
	end
end

function Writer.writeColorSequence(self: Writer, value: ColorSequence)
	local keys = value.Keypoints
	self:writeULEB128(#keys)

	for i = 1, #keys do
		local keypoint = keys[i]
		self:writeF32(keypoint.Time)
		self:writeF32(keypoint.Value.R)
		self:writeF32(keypoint.Value.G)
		self:writeF32(keypoint.Value.B)
	end
end

function Writer.getExtras(self: Writer): { [number]: any, n: number }
	local out = { n = self._extras.n }
	for i = 1, self._extras.n do
		out[i] = self._extras[i]
	end

	return out
end

function Writer.toString(self: Writer): string
	self:alignByte()
	return string.char(table.unpack(self._bytes))
end

return Writer
