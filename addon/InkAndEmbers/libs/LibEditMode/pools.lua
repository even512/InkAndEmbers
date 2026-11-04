-- Ink & Embers: guard for clients without Edit Mode
if not (EventRegistry and EditModeManagerFrame and EditModeSystemSettingsDialog and Enum and Enum.EditModeSettingDisplayType and CreateUnsecuredObjectPool and hooksecurefunc) then return end

local _, ns = ...
local lib
if ns.LibEditMode then
	lib = ns.LibEditMode
else
	local MINOR = 18
	local prevMinor
	lib, prevMinor = LibStub('LibEditMode')
	if prevMinor > MINOR then
		return
	end
end

local Acquire = CreateUnsecuredObjectPool().Acquire
local function acquire(self, parent)
	local obj, new = Acquire(self)
	obj:SetParent(parent)
	return obj, new
end

local pools = {}
function lib.internal:CreatePool(kind, creationFunc, resetterFunc)
	local pool = CreateUnsecuredObjectPool(creationFunc, resetterFunc)
	pool.Acquire = acquire
	pools[kind] = pool
end

function lib.internal:GetPool(kind)
	return pools[kind]
end

function lib.internal:ReleaseAllPools()
	for _, pool in next, pools do
		pool:ReleaseAll()
	end
end
