--!optimize 2

local NetcodeTypes = require(script.Parent.NetcodeTypes)

type TypeDescriptor = NetcodeTypes.TypeDescriptor
type SchemaNode = NetcodeTypes.SchemaNode

local Reader = {}
Reader.__index = Reader

export type Reader = {
	_bytes: { number },
	_pos: number,
	_bitBuffer: number,
	_bitCount: number,
	_extras: { any }?,
	_extraPos: number?,

	new: (data: string) -> Reader,

	readBits: (self: Reader, bitCount: number) -> number,
	alignByte: (self: Reader) -> (),

	readS8: (self: Reader) -> number,
	readS16: (self: Reader) -> number,
	readS24: (self: Reader) -> number,
	readS32: (self: Reader) -> number,

	readU4: (self: Reader) -> number,
	readU8: (self: Reader) -> number,
	readU16: (self: Reader) -> number,
	readU24: (self: Reader) -> number,
	readU32: (self: Reader) -> number,

	readF16: (self: Reader) -> number,
	readF24: (self: Reader) -> number,
	readF32: (self: Reader) -> number,
	readF64: (self: Reader) -> number,

	readString: (self: Reader) -> string,

	readBuffer: (self: Reader) -> buffer,

	readAny: (self: Reader) -> any,

	readBoolean1: (self: Reader) -> boolean,
	readBoolean8: (self: Reader) -> boolean,

	readNumberRange: (self: Reader) -> NumberRange,
	readBrickColor: (self: Reader) -> BrickColor,
	readColor3: (self: Reader) -> Color3,
	readUDim: (self: Reader) -> UDim,
	readUDim2: (self: Reader) -> UDim2,
	readRect: (self: Reader) -> Rect,

	readVector2S16: (self: Reader) -> Vector2,
	readVector2F24: (self: Reader) -> Vector2,
	readVector2F32: (self: Reader) -> Vector2,

	readVector3S16: (self: Reader) -> Vector3,
	readVector3F24: (self: Reader) -> Vector3,
	readVector3F32: (self: Reader) -> Vector3,

	readCFrameF24U8: (self: Reader) -> CFrame,
	readCFrameF32U8: (self: Reader) -> CFrame,
	readCFrameF32U16: (self: Reader) -> CFrame,

	readRegion3: (self: Reader) -> Region3,
	readNumberSequence: (self: Reader) -> NumberSequence,
	readColorSequence: (self: Reader) -> ColorSequence,

	readULEB128: (self: Reader) -> number,
}

function Reader.new(data: string, extras: { any }?): Reader
	local bytes = {} :: { number }
	for i = 1, #data do
		bytes[i] = string.byte(data, i)
	end

	local self = setmetatable({
		_bytes = bytes,
		_pos = 1,
		_bitBuffer = 0,
		_bitCount = 0,
		_extras = extras,
		_extraPos = 1,
	}, Reader)

	return self
end

function Reader.readBits(self: Reader, bitCount: number): number
	local need = bitCount
	while self._bitCount < need do
		if self._pos > #self._bytes then
			error("readBits: EOF")
		end
		local nextByte = self._bytes[self._pos]
		self._pos += 1
		self._bitBuffer = bit32.bor(self._bitBuffer, bit32.lshift(nextByte, self._bitCount))
		self._bitCount += 8
	end

	local mask = bit32.lshift(1, bitCount) - 1
	local v = bit32.band(self._bitBuffer, mask)
	self._bitBuffer = bit32.rshift(self._bitBuffer, bitCount)
	self._bitCount -= bitCount
	return v
end

function Reader.alignByte(self: Reader)
	self._bitBuffer = 0
	self._bitCount = 0
end

local function readUBytes(self: Reader, count: number): number
	self:alignByte()
	local v = 0
	local shift = 0
	for _ = 1, count do
		if self._pos > #self._bytes then
			error("readUBytes: EOF")
		end
		local b = self._bytes[self._pos]
		self._pos += 1
		v = v + bit32.lshift(b, shift)
		shift += 8
	end
	return v
end

local function fromTwos(value: number, bits: number): number
	local max = bit32.lshift(1, bits)
	local half = bit32.rshift(max, 1)
	if value >= half then
		value -= max
	end
	return value
end

function Reader.readU4(self: Reader): number
	return self:readBits(4)
end

function Reader.readU8(self: Reader): number
	return readUBytes(self, 1)
end

function Reader.readU16(self: Reader): number
	return readUBytes(self, 2)
end

function Reader.readU24(self: Reader): number
	return readUBytes(self, 3)
end

function Reader.readU32(self: Reader): number
	return readUBytes(self, 4)
end

function Reader.readS8(self: Reader): number
	return fromTwos(self:readU8(), 8)
end

function Reader.readS16(self: Reader): number
	return fromTwos(self:readU16(), 16)
end

function Reader.readS24(self: Reader): number
	return fromTwos(self:readU24(), 24)
end

function Reader.readS32(self: Reader): number
	self:alignByte()
	local u = self:readU32()
	if u >= 0x80000000 then
		return u - 0x100000000
	else
		return u
	end
end

local function unpackF32LE(self: Reader): number
	local u = self:readU32()
	local sign = bit32.band(bit32.rshift(u, 31), 1)
	local E = bit32.band(bit32.rshift(u, 23), 0xFF)
	local M = bit32.band(u, 0x7FFFFF)

	if E == 0xFF then
		if M == 0 then
			return (sign == 1) and -math.huge or math.huge
		else
			return 0 / 0 -- NaN
		end
	elseif E == 0 then
		if M == 0 then
			return (sign == 1) and -0 or 0
		end
		local m = M / 2 ^ 23
		local x = m * 2 ^ (1 - 127)
		return (sign == 1) and -x or x
	else
		local m = 1 + (M / 2 ^ 23)
		local x = m * 2 ^ (E - 127)
		return (sign == 1) and -x or x
	end
end

local function unpackF64LE(self: Reader): number
	local lo = self:readU32()
	local hi = self:readU32()
	local sign = bit32.band(bit32.rshift(hi, 31), 1)
	local E = bit32.band(bit32.rshift(hi, 20), 0x7FF)
	local Mhi = bit32.band(hi, 0xFFFFF)
	local M = Mhi * 2 ^ 32 + lo

	if E == 0x7FF then
		if M == 0 then
			return (sign == 1) and -math.huge or math.huge
		else
			return 0 / 0
		end
	elseif E == 0 then
		if M == 0 then
			return (sign == 1) and -0 or 0
		end
		local m = M / 2 ^ 52
		local x = m * 2 ^ (1 - 1023)
		return (sign == 1) and -x or x
	else
		local m = 1 + (M / 2 ^ 52)
		local x = m * 2 ^ (E - 1023)
		return (sign == 1) and -x or x
	end
end

function Reader.readF16(self: Reader): number
	local u = self:readU16()
	local sign = bit32.band(bit32.rshift(u, 15), 1)
	local E = bit32.band(bit32.rshift(u, 10), 0x1F)
	local M = bit32.band(u, 0x3FF)

	if E == 0x1F then
		if M == 0 then
			return (sign == 1) and -math.huge or math.huge
		else
			return 0 / 0
		end
	elseif E == 0 then
		if M == 0 then
			return (sign == 1) and -0 or 0
		end
		local m = M / 2 ^ 10
		local x = m * 2 ^ (1 - 15)
		return (sign == 1) and -x or x
	else
		local m = 1 + (M / 2 ^ 10)
		local x = m * 2 ^ (E - 15)
		return (sign == 1) and -x or x
	end
end

function Reader.readF24(self: Reader): number
	local s24 = self:readS24()
	return s24 / 65536
end

function Reader.readF32(self: Reader): number
	return unpackF32LE(self)
end

function Reader.readF64(self: Reader): number
	self:alignByte()
	local lo = self:readU32()
	local hi = self:readU32()

	local sign = bit32.rshift(hi, 31) ~= 0 and -1 or 1
	local exp = bit32.band(bit32.rshift(hi, 20), 0x7FF)
	local mant_hi = bit32.band(hi, 0xFFFFF)
	local mant = mant_hi * 4294967296 + lo -- 2^32

	if exp == 0x7FF then
		if mant == 0 then
			return sign * math.huge
		else
			-- NaN
			return 0 / 0
		end
	elseif exp == 0 then
		if mant == 0 then
			return sign * 0
		end
		return sign * (mant / 4503599627370496) * 2 ^ (1 - 1023) -- 2^52
	else
		return sign * (1 + mant / 4503599627370496) * 2 ^ (exp - 1023)
	end
end

function Reader.readULEB128(self: Reader): number
	self:alignByte()
	local result = 0
	local shift = 0
	while true do
		if self._pos > #self._bytes then
			error("readULEB128: EOF")
		end
		local b = self._bytes[self._pos]
		self._pos += 1
		result = result + bit32.lshift(bit32.band(b, 0x7F), shift)
		if bit32.band(b, 0x80) == 0 then
			break
		end
		shift += 7
	end
	return result
end

function Reader.readString(self: Reader): string
	local n = self:readULEB128()
	self:alignByte()
	if self._pos + n - 1 > #self._bytes then
		error("readString: EOF")
	end
	local out = table.create(n)
	for i = 1, n do
		out[i] = string.char(self._bytes[self._pos])
		self._pos += 1
	end
	return table.concat(out)
end

function Reader.readBuffer(self: Reader): buffer
	local n = self:readULEB128()
	self:alignByte()
	if self._pos + n - 1 > #self._bytes then
		error("readBuffer: EOF")
	end
	local buf = buffer.create(n)
	for i = 0, n - 1 do
		buffer.writeu8(buf, i, self._bytes[self._pos])
		self._pos += 1
	end
	return buf
end

function Reader.readAny(self: Reader): any
	local extras = self._extras
	assert(extras ~= nil, "readAny: no extra args present")

	local i = self._extraPos or 1
	assert(i <= extras.n, "readAny: ran out of extra args")

	local v = extras[i]
	self._extraPos = i + 1

	return v
end

function Reader.readBoolean1(self: Reader): boolean
	return self:readBits(1) ~= 0
end

function Reader.readBoolean8(self: Reader): boolean
	return self:readU8() ~= 0
end

function Reader.readNumberRange(self: Reader): NumberRange
	local mn = self:readF32()
	local mx = self:readF32()
	return NumberRange.new(mn, mx)
end

function Reader.readBrickColor(self: Reader): BrickColor
	return BrickColor.new(self:readU16())
end

function Reader.readColor3(self: Reader): Color3
	local r = self:readF32()
	local g = self:readF32()
	local b = self:readF32()
	return Color3.new(r, g, b)
end

function Reader.readUDim(self: Reader): UDim
	local scale = self:readF32()
	local offset = self:readS16()
	return UDim.new(scale, offset)
end

function Reader.readUDim2(self: Reader): UDim2
	local sx = self:readF32()
	local ox = self:readS16()
	local sy = self:readF32()
	local oy = self:readS16()
	return UDim2.new(sx, ox, sy, oy)
end

function Reader.readRect(self: Reader): Rect
	local minx = self:readF32()
	local miny = self:readF32()
	local maxx = self:readF32()
	local maxy = self:readF32()
	return Rect.new(minx, miny, maxx, maxy)
end

function Reader.readVector2S16(self: Reader): Vector2
	local x = self:readS16()
	local y = self:readS16()
	return Vector2.new(x, y)
end

function Reader.readVector2F24(self: Reader): Vector2
	local x = self:readF24()
	local y = self:readF24()
	return Vector2.new(x, y)
end

function Reader.readVector2F32(self: Reader): Vector2
	local x = self:readF32()
	local y = self:readF32()
	return Vector2.new(x, y)
end

function Reader.readVector3S16(self: Reader): Vector3
	local x = self:readS16()
	local y = self:readS16()
	local z = self:readS16()
	return Vector3.new(x, y, z)
end

function Reader.readVector3F24(self: Reader): Vector3
	local x = self:readF24()
	local y = self:readF24()
	local z = self:readF24()
	return Vector3.new(x, y, z)
end

function Reader.readVector3F32(self: Reader): Vector3
	local x = self:readF32()
	local y = self:readF32()
	local z = self:readF32()
	return Vector3.new(x, y, z)
end

local function U8ToQuat(u: number): number
	return ((u / 255) * 2) - 1
end

local function U16ToQuat(u: number): number
	return ((u / 65535) * 2) - 1
end

local function QuatToMatrix(
	qx: number,
	qy: number,
	qz: number,
	qw: number
): (number, number, number, number, number, number, number, number, number)
	local mag = math.sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
	if mag > 0 then
		qx /= mag
		qy /= mag
		qz /= mag
		qw /= mag
	else
		qx, qy, qz, qw = 0, 0, 0, 1
	end

	local xx = qx * qx
	local yy = qy * qy
	local zz = qz * qz
	local xy = qx * qy
	local xz = qx * qz
	local yz = qy * qz
	local wx = qw * qx
	local wy = qw * qy
	local wz = qw * qz

	local r00 = 1 - 2 * (yy + zz)
	local r11 = 1 - 2 * (xx + zz)
	local r22 = 1 - 2 * (xx + yy)
	local r01 = 2 * (xy - wz)
	local r10 = 2 * (xy + wz)
	local r02 = 2 * (xz + wy)
	local r20 = 2 * (xz - wy)
	local r12 = 2 * (yz - wx)
	local r21 = 2 * (yz + wx)

	return r00, r01, r02, r10, r11, r12, r20, r21, r22
end

function Reader.readCFrameF24U8(self: Reader): CFrame
	local px = self:readF24()
	local py = self:readF24()
	local pz = self:readF24()

	local qx = U8ToQuat(self:readU8())
	local qy = U8ToQuat(self:readU8())
	local qz = U8ToQuat(self:readU8())
	local qw = U8ToQuat(self:readU8())

	local r00, r01, r02, r10, r11, r12, r20, r21, r22 = QuatToMatrix(qx, qy, qz, qw)
	return CFrame.new(px, py, pz, r00, r01, r02, r10, r11, r12, r20, r21, r22)
end

function Reader.readCFrameF32U8(self: Reader): CFrame
	local px = self:readF32()
	local py = self:readF32()
	local pz = self:readF32()

	local qx = U8ToQuat(self:readU8())
	local qy = U8ToQuat(self:readU8())
	local qz = U8ToQuat(self:readU8())
	local qw = U8ToQuat(self:readU8())

	local r00, r01, r02, r10, r11, r12, r20, r21, r22 = QuatToMatrix(qx, qy, qz, qw)
	return CFrame.new(px, py, pz, r00, r01, r02, r10, r11, r12, r20, r21, r22)
end

function Reader.readCFrameF32U16(self: Reader): CFrame
	local px = self:readF32()
	local py = self:readF32()
	local pz = self:readF32()

	local qx = U16ToQuat(self:readU16())
	local qy = U16ToQuat(self:readU16())
	local qz = U16ToQuat(self:readU16())
	local qw = U16ToQuat(self:readU16())

	local r00, r01, r02, r10, r11, r12, r20, r21, r22 = QuatToMatrix(qx, qy, qz, qw)
	return CFrame.new(px, py, pz, r00, r01, r02, r10, r11, r12, r20, r21, r22)
end

function Reader.readRegion3(self: Reader): Region3
	local minx = self:readF32()
	local miny = self:readF32()
	local minz = self:readF32()
	local maxx = self:readF32()
	local maxy = self:readF32()
	local maxz = self:readF32()
	local minV = Vector3.new(minx, miny, minz)
	local maxV = Vector3.new(maxx, maxy, maxz)
	return Region3.new(minV, maxV)
end

function Reader.readNumberSequence(self: Reader): NumberSequence
	local n = self:readULEB128()
	local keys = table.create(n)
	for i = 1, n do
		local t = self:readF32()
		local v = self:readF32()
		local e = self:readF32()
		keys[i] = NumberSequenceKeypoint.new(t, v, e)
	end
	return NumberSequence.new(keys)
end

function Reader.readColorSequence(self: Reader): ColorSequence
	local n = self:readULEB128()
	local keys = table.create(n)
	for i = 1, n do
		local t = self:readF32()
		local r = self:readF32()
		local g = self:readF32()
		local b = self:readF32()
		keys[i] = ColorSequenceKeypoint.new(t, Color3.new(r, g, b))
	end
	return ColorSequence.new(keys)
end

return Reader
