local Inventory_Events = {}

--// OOP //--

local MetaEvents = {}
MetaEvents.__index = MetaEvents

--// Modules //--

local Networker = require(game.ReplicatedStorage.Network.Networker)
local Items = require(game.ServerStorage.Data.Items)

--// Types //--

export type events = {
	new_item: string,
	destroy_item: string,
	update_item: string,
	manage_item_from_client: string,
	get_item_from_client: string,
	Fire: (self: events, typeOfRemote: "new_item" | "destroy_item" | "update_item", data: {}) -> ()
	
}

----------------
--// System //--
----------------

function Inventory_Events.New(plrID): events
	
	return setmetatable({
		new_item = plrID.."inventory_newitem",
		destroy_item = plrID.."inventory_destroyitem",
		update_item = plrID.."inventory_updateitem",
		manage_item_from_client = plrID.."manage_item_cl",
		get_item_from_client = plrID.."get_item_from_client",
	}, MetaEvents) :: events
end

function Inventory_Events.Destroy(events)
	
	for name, eventid in pairs(events) do
		
		Networker.DestroyEvent(eventid)
	end
end

-----------------------
--// Events Class  //--
-----------------------

function MetaEvents:Fire(typeOfRemote: "new_item" | "destroy_item" | "update_item", data)
	
	local eventID = self[typeOfRemote]
	if not eventID then return end
	
	if data[1] then warn("DATA IS NOT SERIALIZED") return end
	
	Networker.Fire(eventID, {
		Data = data,
		Type = typeOfRemote,
		Timestamp = os.clock(),
		Player = data.Player,
		Display = Items[data.Name].Display
	}, {"RE", "BE"})
end

function MetaEvents:Destroy()
	
	Inventory_Events.Destroy(self)
end

return Inventory_Events