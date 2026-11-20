--[[
	FFWL — Forcefield Whitelist (адаптация под Bendable Combine Forcefield)

	Мод: prop_forcefield + prop_forcefield_field (автор bol_snaphak)
	Эта версия НЕ добавляет свой хук ShouldCollide (он ломался из-за порядка
	вызова хуков), а расширяет метод ShouldCollideWith самого поля:
	вайтлист игроков/редакторов/NPC-классов проверяется внутри родной логики.

	Возможности:
	 - вайтлист игроков (SteamID), редакторов, NPC-классов + штатный вайтлист команд мода;
	 - меню Forcefield Manager в тёмном стиле: E по полю, пункт в контекстном меню, ffwl_menu, чат !ffmenu;
	 - NPC из вайтлиста проходят поле (включая обход ИИ-блокировки в зоне у поля);
	 - через поле проходят ТОЛЬКО вписанные игроки и редакторы — админ без вписывания не пройдёт;
	 - админ / ULX-флаг forcefield_edit / владелец поля (CPPI) дают право редактирования списков;
	 - диагностика: ffwl_scan, ffwl_debug.

	Списки хранятся на самой сущности поля и живут, пока поле существует.
]]

local FIELD_CLASS = "prop_forcefield_field"
local PLATFORM_CLASS = "prop_forcefield"

--------------------------------------------------------------------
-- SHARED: расширение ShouldCollideWith мода
--------------------------------------------------------------------

local function WrapShouldCollideWith(target)
	if not target or not target.ShouldCollideWith or target.FFWL_Patched then return end
	target.FFWL_Patched = true

	local original = target.ShouldCollideWith
	target.ShouldCollideWith = function(self, other)
		if not self:GetEnabled() then return original(self, other) end
		if not IsValid(other) then return original(self, other) end

		if other:IsPlayer() then
			-- Поимённый вайтлист игроков
			local players = self.FFWL_Players
			if players and players[other:SteamID()] then return false end

			-- Вписанные редакторы
			local editors = self.FFWL_Editors
			if editors and editors[other:SteamID()] then return false end

		elseif other:IsNPC() or other:IsNextBot() then
			-- Вайтлист по классам (npc_vj_automaton_trooper, npc_manhack, ...)
			local classes = self.FFWL_NPCClasses
			if classes and classes[other:GetClass()] then return false end
		end

		return original(self, other)
	end
end

local function TryPatchClass()
	local stored = scripted_ents.GetStored(FIELD_CLASS)
	if not (stored and stored.t) then return false end

	WrapShouldCollideWith(stored.t)
	return stored.t.FFWL_Patched or false
end

hook.Add("InitPostEntity", "FFWL_Init", function()
	local patched = TryPatchClass()
	if SERVER then
		if patched then
			print("[FFWL] Адаптация под " .. FIELD_CLASS .. " загружена")
		else
			print("[FFWL] ВНИМАНИЕ: класс " .. FIELD_CLASS .. " не найден — мод силовых полей не установлен?")
		end
	else
		print("[FFWL] Клиентская часть загружена")
	end
end)

hook.Add("OnEntityCreated", "FFWL_EntCreated", function(ent)
	if ent:GetClass() ~= FIELD_CLASS then return end
	timer.Simple(0, function()
		if not IsValid(ent) then return end

		TryPatchClass()

		-- На случай, если класс так и не нашёлся: обёртка конкретной сущности
		local stored = scripted_ents.GetStored(FIELD_CLASS)
		if not (stored and stored.t and stored.t.FFWL_Patched) then
			WrapShouldCollideWith(ent)
		end
	end)
end)

--------------------------------------------------------------------
-- SERVER: данные, net-сообщения, права, NPC-зона
--------------------------------------------------------------------

if SERVER then
	util.AddNetworkString("ffwl_request")
	util.AddNetworkString("ffwl_data")
	util.AddNetworkString("ffwl_action")
	util.AddNetworkString("ffwl_notify")

	if ULib then
		ULib.ucl.registerAccess("forcefield_edit", {"superadmin", "admin"}, "Доступ к менеджеру силовых полей (FFWL)", "Forcefields")
	end

	local function HasEditAccess(ply)
		if not IsValid(ply) then return false end
		if ply:IsAdmin() then return true end
		if ULib and ULib.ucl and ULib.ucl.query(ply, "forcefield_edit") then return true end
		return false
	end

	local function IsOwner(ply, ent)
		if not IsValid(ply) then return false end
		if CPPI and ent.CPPIGetOwner and ent:CPPIGetOwner() == ply then return true end
		return false
	end

	local function CanEditField(ply, ent)
		if not IsValid(ent) or ent:GetClass() ~= FIELD_CLASS then return false end
		if HasEditAccess(ply) then return true end
		return IsOwner(ply, ent)
	end

	local function Notify(ply, text)
		net.Start("ffwl_notify")
		net.WriteString(text)
		net.Send(ply)
	end

	local ACTION_LIST = {
		addplayer = "Players", removeplayer = "Players",
		addeditor = "Editors", removeeditor = "Editors",
		addnpcclass = "NPCClasses", removenpcclass = "NPCClasses",
	}

	local function GetList(ent, key)
		local list = ent["FFWL_" .. key]
		if not list then
			list = {}
			ent["FFWL_" .. key] = list
		end
		return list
	end

	net.Receive("ffwl_action", function(len, ply)
		local ent = net.ReadEntity()
		if not CanEditField(ply, ent) then return end

		local action = net.ReadString()
		local value = net.ReadString() or ""

		local listKey = ACTION_LIST[action]
		if listKey then
			if value == "" then return end

			local list = GetList(ent, listKey)

			if action:StartsWith("add") then
				if list[value] then return end
				list[value] = true
				Notify(ply, "[FFWL] Добавлено (" .. listKey .. "): " .. value)
			else
				if not list[value] then return end
				list[value] = nil
				Notify(ply, "[FFWL] Удалено (" .. listKey .. "): " .. value)
			end

			ent:CollisionRulesChanged()
			return
		end

		if action == "addteam" then
			local teamId = tonumber(value)
			if not teamId or not team.Valid(teamId) then return end
			if ent:IsTeamWhitelisted(teamId) then return end

			ent:AddTeamToWhitelist(teamId)
			Notify(ply, "[FFWL] Команда добавлена в вайтлист")
		elseif action == "removeteam" then
			local teamId = tonumber(value)
			if not teamId or not team.Valid(teamId) then return end
			if not ent:IsTeamWhitelisted(teamId) then return end

			ent:RemoveTeamFromWhitelist(teamId)
			Notify(ply, "[FFWL] Команда удалена из вайтлиста")
		end
	end)

	net.Receive("ffwl_request", function(len, ply)
		local ent = net.ReadEntity()
		if not CanEditField(ply, ent) then return end

		local function CollectIDList(list)
			local result = {}
			for sid in pairs(list or {}) do
				local name = nil
				for _, p in ipairs(player.GetAll()) do
					if p:SteamID() == sid then
						name = p:Nick()
						break
					end
				end
				if name then
					result[#result + 1] = sid .. " — " .. name
				else
					result[#result + 1] = sid
				end
			end
			table.sort(result)
			return result
		end

		local function CollectRawIDs(list)
			local result = {}
			for sid in pairs(list or {}) do
				result[#result + 1] = sid
			end
			table.sort(result)
			return result
		end

		local teams, teamIds = {}, {}
		for teamId, teamData in pairs(team.GetAllTeams()) do
			if ent:IsTeamWhitelisted(teamId) then
				teams[#teams + 1] = teamData.Name
				teamIds[#teamIds + 1] = tostring(teamId)
			end
		end

		local npcclasses = {}
		for cls in pairs(ent.FFWL_NPCClasses or {}) do
			npcclasses[#npcclasses + 1] = cls
		end
		table.sort(npcclasses)

		net.Start("ffwl_data")
		net.WriteEntity(ent)
		net.WriteTable({
			Players = CollectIDList(ent.FFWL_Players),
			PlayerIds = CollectRawIDs(ent.FFWL_Players),
			Editors = CollectIDList(ent.FFWL_Editors),
			EditorIds = CollectRawIDs(ent.FFWL_Editors),
			NPCClasses = npcclasses,
			Teams = teams,
			TeamIds = teamIds,
		})
		net.Send(ply)
	end)

	-- Зона прохода для вайтлистных NPC: ИИ перестаёт видеть поле как препятствие
	local NEAR_DISTANCE = 170
	local FAR_DISTANCE = 250
	local FFWL_INFIELD = {}

	timer.Create("FFWL_NPCZone", 0.1, 0, function()
		for npc, field in pairs(FFWL_INFIELD) do
			if not IsValid(npc) then
				FFWL_INFIELD[npc] = nil
			elseif not IsValid(field) or npc:GetPos():Distance(field:GetPos()) > FAR_DISTANCE then
				FFWL_INFIELD[npc] = nil
				npc:SetCollisionGroup(npc.FFWL_OldCollisionGroup or COLLISION_GROUP_NONE)
				npc.FFWL_OldCollisionGroup = nil
			end
		end

		for _, field in ipairs(ents.FindByClass(FIELD_CLASS)) do
			local classes = field.FFWL_NPCClasses
			if not classes then continue end

			local classCount = 0
			for _ in pairs(classes) do classCount = classCount + 1 end
			if classCount == 0 then continue end

			for _, npc in ipairs(ents.FindInSphere(field:GetPos(), FAR_DISTANCE)) do
				if not (npc:IsNPC() or npc:IsNextBot()) then continue end
				if not classes[npc:GetClass()] then continue end
				if FFWL_INFIELD[npc] then continue end

				if npc:GetPos():Distance(field:GetPos()) <= NEAR_DISTANCE then
					FFWL_INFIELD[npc] = field
					npc.FFWL_OldCollisionGroup = npc:GetCollisionGroup()
					npc:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
				end
			end
		end
	end)

	hook.Add("PlayerDisconnected", "FFWL_CleanupEditor", function(ply)
		local sid = ply:SteamID()
		for _, field in ipairs(ents.FindByClass(FIELD_CLASS)) do
			local editors = field.FFWL_Editors
			if editors and editors[sid] then
				editors[sid] = nil
				field:CollisionRulesChanged()
			end
		end
	end)

	concommand.Add("ffwl_debug", function(ply)
		if not IsValid(ply) or not ply:IsAdmin() then return end

		local eyePos = ply:EyePos()
		local aimDir = ply:GetAimVector()
		local best, bestDist = nil, 120

		for _, ent in ipairs(ents.FindByClass(FIELD_CLASS)) do
			local center = ent:WorldSpaceCenter()
			local toCenter = center - eyePos
			local proj = toCenter:Dot(aimDir)
			if proj < 10 then continue end
			local closestPoint = eyePos + aimDir * proj
			local distance = closestPoint:Distance(center)
			if distance < bestDist then
				best, bestDist = ent, distance
			end
		end

		if not IsValid(best) then
			print("[FFWL] ffwl_debug: поле не найдено")
			return
		end

		print("=== [FFWL] Отладка поля ===")
		print("  Entity: " .. tostring(best) .. " (" .. best:GetClass() .. ")")
		print("  Enabled: " .. tostring(best:GetEnabled()))
		print("  Type: " .. tostring(best:GetForcefieldType()))

		local playerKeys = {}
		for sid in pairs(best.FFWL_Players or {}) do playerKeys[#playerKeys + 1] = sid end
		print("  Игроки (SteamID): " .. table.concat(playerKeys, ", "))

		local editorKeys = {}
		for sid in pairs(best.FFWL_Editors or {}) do editorKeys[#editorKeys + 1] = sid end
		print("  Редакторы: " .. table.concat(editorKeys, ", "))

		local classKeys = {}
		for cls in pairs(best.FFWL_NPCClasses or {}) do classKeys[#classKeys + 1] = cls end
		print("  NPC-классы: " .. table.concat(classKeys, ", "))

		local teamList = {}
		for teamId, teamData in pairs(team.GetAllTeams()) do
			if best:IsTeamWhitelisted(teamId) then
				teamList[#teamList + 1] = teamData.Name
			end
		end
		print("  Команды: " .. table.concat(teamList, ", "))

		print("  Твой доступ: admin=" .. tostring(ply:IsAdmin()) .. " | flag=" .. tostring(HasEditAccess(ply)) .. " | owner=" .. tostring(IsOwner(ply, best)))
		print("=== конец ===")
	end)
end

--------------------------------------------------------------------
-- SHARED: диагностика
--------------------------------------------------------------------

concommand.Add("ffwl_scan", function(ply)
	if IsValid(ply) and not ply:IsAdmin() then return end

	local fields = ents.FindByClass(FIELD_CLASS)
	local platforms = ents.FindByClass(PLATFORM_CLASS)

	print("[FFWL] Полей " .. FIELD_CLASS .. " на карте: " .. #fields)
	for _, ent in ipairs(fields) do
		local enabled = "?"
		if ent.GetEnabled then enabled = tostring(ent:GetEnabled()) end
		local ftype = "?"
		if ent.GetForcefieldType then ftype = tostring(ent:GetForcefieldType()) end
		print("  " .. tostring(ent) .. " | enabled=" .. enabled .. " | type=" .. ftype)
	end
	print("[FFWL] Платформ (эмиттеров) " .. PLATFORM_CLASS .. ": " .. #platforms)
end)

--------------------------------------------------------------------
-- CLIENT: стилизованное меню, поиск поля взглядом, контекстное меню
--------------------------------------------------------------------

if CLIENT then
	surface.CreateFont("FFWL_Title", { font = "Roboto", size = 18, weight = 700, extended = true })
	surface.CreateFont("FFWL_Tab", { font = "Roboto", size = 14, weight = 600, extended = true })
	surface.CreateFont("FFWL_Item", { font = "Roboto", size = 14, weight = 500, extended = true })

	local COL_BG      = Color(21, 25, 31)
	local COL_HEADER  = Color(30, 36, 44)
	local COL_ROW_A   = Color(28, 33, 41)
	local COL_ROW_B   = Color(24, 28, 35)
	local COL_LINE    = Color(48, 58, 70)
	local COL_TEXT    = Color(214, 224, 232)
	local COL_DIM     = Color(122, 134, 147)
	local COL_ACCENT  = Color(0, 188, 212)
	local COL_ACCENT2 = Color(130, 220, 255)
	local COL_RED     = Color(232, 84, 84)

	local function ClientCanEdit(ent)
		local ply = LocalPlayer()
		if not IsValid(ply) then return false end
		if ply:IsAdmin() then return true end
		if ULib and ULib.ucl and ULib.ucl.query(ply, "forcefield_edit") then return true end
		if CPPI and ent.CPPIGetOwner and ent:CPPIGetOwner() == ply then return true end
		return false
	end

	-- Поле ловится геометрией: трейс сквозь него проходит (мод пускает MASK_USE)
	local function GetLookedField()
		local ply = LocalPlayer()
		if not IsValid(ply) then return end

		local eyePos = ply:EyePos()
		local aimDir = ply:GetAimVector()

		local best, bestDist = nil, 70
		for _, ent in ipairs(ents.FindByClass(FIELD_CLASS)) do
			if not IsValid(ent) then continue end
			local center = ent:WorldSpaceCenter()
			local toCenter = center - eyePos
			local proj = toCenter:Dot(aimDir)
			if proj < 10 then continue end
			local closestPoint = eyePos + aimDir * proj
			local distance = closestPoint:Distance(center)
			if distance < bestDist then
				best, bestDist = ent, distance
			end
		end

		return best
	end

	local currentEntity, currentMenu
	local listData = {}
	local activeTab = "players"

	local TABS = {
		{ id = "players", label = "Игроки",      remove = "removeplayer" },
		{ id = "teams",   label = "Команды",     remove = "removeteam" },
		{ id = "editors", label = "Редакторы",   remove = "removeeditor" },
		{ id = "npcs",    label = "NPC-классы",  remove = "removenpcclass" },
	}

	local function RequestData()
		if not IsValid(currentEntity) then return end
		net.Start("ffwl_request")
		net.WriteEntity(currentEntity)
		net.SendToServer()
	end

	local function SendAction(action, value)
		if not IsValid(currentEntity) then return end
		net.Start("ffwl_action")
		net.WriteEntity(currentEntity)
		net.WriteString(action)
		net.WriteString(value or "")
		net.SendToServer()

		timer.Simple(0.15, function()
			if not IsValid(currentEntity) then return end
			RequestData()
		end)
	end

	local function TabItems(tabId)
		local out = {}

		if tabId == "players" then
			local ids = listData.PlayerIds or {}
			for i, text in ipairs(listData.Players or {}) do
				out[#out + 1] = { text = text, id = ids[i] or text }
			end
		elseif tabId == "teams" then
			local ids = listData.TeamIds or {}
			for i, text in ipairs(listData.Teams or {}) do
				out[#out + 1] = { text = text, id = ids[i] or text }
			end
		elseif tabId == "editors" then
			local ids = listData.EditorIds or {}
			for i, text in ipairs(listData.Editors or {}) do
				out[#out + 1] = { text = text, id = ids[i] or text }
			end
		elseif tabId == "npcs" then
			for _, cls in ipairs(listData.NPCClasses or {}) do
				out[#out + 1] = { text = cls, id = cls }
			end
		end

		return out
	end

	net.Receive("ffwl_data", function()
		if not IsValid(currentEntity) then return end
		local ent = net.ReadEntity()
		if ent ~= currentEntity then return end

		listData = net.ReadTable() or {}

		if not IsValid(currentMenu) then return end
		local refresh = currentMenu.FFWL_Refresh
		if refresh then refresh() end
	end)

	net.Receive("ffwl_notify", function()
		chat.AddText(Color(120, 220, 255), net.ReadString())
	end)

	local function IDPickerMenu(ids, callback)
		local menu = DermaMenu()
		if #ids == 0 then
			menu:AddOption("(список пуст)", function() end)
		else
			for _, id in ipairs(ids) do
				menu:AddOption(id, function() callback(id) end)
			end
		end
		menu:Open()
	end

	local function PlayerPickerMenu(callback)
		local menu = DermaMenu()
		for _, p in ipairs(player.GetAll()) do
			menu:AddOption(p:Nick() .. " (" .. p:SteamID() .. ")", function() callback(p:SteamID()) end)
		end
		menu:AddSpacer()
		menu:AddOption("Вписать SteamID вручную", function()
			Derma_StringRequest("FFWL", "SteamID игрока (например STEAM_0:1:12345678):", "", function(text)
				if text ~= "" then callback(text) end
			end)
		end)
		menu:Open()
	end

	local function AddActionForTab(tabId)
		if tabId == "players" then
			return function()
				PlayerPickerMenu(function(sid) SendAction("addplayer", sid) end)
			end
		elseif tabId == "teams" then
			return function()
				local menu = DermaMenu()
				for teamId, teamData in pairs(team.GetAllTeams()) do
					menu:AddOption(teamData.Name, function() SendAction("addteam", tostring(teamId)) end)
				end
				menu:Open()
			end
		elseif tabId == "editors" then
			return function()
				PlayerPickerMenu(function(sid) SendAction("addeditor", sid) end)
			end
		elseif tabId == "npcs" then
			return function()
				Derma_StringRequest("FFWL", "Класс NPC (например npc_vj_automaton_trooper):", "", function(text)
					if text ~= "" then SendAction("addnpcclass", text) end
				end)
			end
		end
		return function() end
	end

	local function RebuildList(listPanel)
		listPanel:Clear()

		local items = TabItems(activeTab)

		if #items == 0 then
			local empty = vgui.Create("DLabel", listPanel)
			empty:Dock(TOP)
			empty:SetTall(40)
			empty:SetText("— пусто —")
			empty:SetFont("FFWL_Item")
			empty:SetTextColor(COL_DIM)
			empty:SetContentAlignment(5)
			return
		end

		for i, item in ipairs(items) do
			local row = vgui.Create("Panel", listPanel)
			row:Dock(TOP)
			row:SetTall(26)
			row:DockMargin(0, 0, 0, 3)

			local rowPaint = function(self, w, h)
				local bg = (i % 2 == 0) and COL_ROW_A or COL_ROW_B
				if self:IsHovered() then bg = COL_HEADER end
				draw.RoundedBox(3, 0, 0, w, h, bg)
				draw.RoundedBoxEx(3, 0, 0, 3, h, COL_ACCENT, true, false, false, true)
			end

			local label = vgui.Create("DLabel", row)
			label:Dock(FILL)
			label:DockMargin(10, 0, 0, 0)
			label:SetFont("FFWL_Item")
			label:SetTextColor(COL_TEXT)
			label:SetText(item.text)
			label:SetTooltip(item.text)

			local del = vgui.Create("DButton", row)
			del:Dock(RIGHT)
			del:SetWide(28)
			del:SetText("")
			del:SetTooltip("Убрать из списка")
			del.Paint = function(self, w, h)
				draw.SimpleText("✕", "FFWL_Item", w / 2, h / 2, self:IsHovered() and COL_RED or COL_DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
			del.DoClick = function()
				for _, tab in ipairs(TABS) do
					if tab.id == activeTab then
						SendAction(tab.remove, item.id)
						return
					end
				end
			end

			row.Paint = rowPaint
		end
	end

	local function OpenMenu(ent)
		if not IsValid(ent) then return end

		if not ClientCanEdit(ent) then
			chat.AddText(Color(255, 100, 100), "[FFWL] Нет прав для редактирования этого поля")
			return
		end

		currentEntity = ent
		activeTab = "players"
		RequestData()

		if IsValid(currentMenu) then currentMenu:Remove() end

		local frame = vgui.Create("DFrame")
		currentMenu = frame
		frame:SetSize(360, 470)
		frame:Center()
		frame:SetTitle("")
		frame:MakePopup()

		frame.Paint = function(self, w, h)
			draw.RoundedBox(6, 0, 0, w, h, COL_BG)
			draw.RoundedBoxEx(6, 0, 0, w, 30, COL_HEADER, true, true, false, false)
			draw.RoundedBoxEx(6, 0, 30, w, 2, COL_ACCENT, false, false, true, true)
			draw.SimpleText("FORCEFIELD MANAGER", "FFWL_Title", 14, 15, COL_ACCENT2, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			draw.SimpleText(tostring(ent), "FFWL_Item", w - 14, 15, COL_DIM, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		end

		-- Вкладки
		local tabBar = vgui.Create("Panel", frame)
		tabBar:Dock(TOP)
		tabBar:SetTall(30)
		tabBar:DockMargin(10, 12, 10, 0)

		for _, tab in ipairs(TABS) do
			local btn = vgui.Create("DButton", tabBar)
			btn:Dock(LEFT)
			btn:SetWide(80)
			btn:SetText("")
			btn.Paint = function(self, w, h)
				local isActive = (activeTab == tab.id)
				if isActive or self:IsHovered() then
					draw.RoundedBox(4, 0, 0, w, h, COL_HEADER)
				end
				if isActive then
					draw.RoundedBoxEx(4, 0, h - 3, w, 3, COL_ACCENT, false, false, true, true)
				end
				local col = isActive and COL_ACCENT2 or COL_DIM
				if self:IsHovered() and not isActive then col = COL_TEXT end
				draw.SimpleText(tab.label, "FFWL_Tab", w / 2, h / 2 - 1, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
			btn.DoClick = function()
				if activeTab == tab.id then return end
				activeTab = tab.id
				if IsValid(currentMenu) and currentMenu.FFWL_Refresh then currentMenu.FFWL_Refresh() end
			end
		end

		-- Список записей
		local scroll = vgui.Create("DScrollPanel", frame)
		scroll:Dock(FILL)
		scroll:DockMargin(10, 10, 10, 0)
		frame.FFWL_ListPanel = scroll

		local vbar = scroll:GetVBar()
		vbar:SetWide(6)
		vbar.Paint = function(self, w, h) draw.RoundedBox(3, 0, 0, w, h, COL_HEADER) end
		vbar.btnGrip.Paint = function(self, w, h) draw.RoundedBox(3, 0, 0, w, h, COL_LINE) end
		vbar.btnUp.Paint = function() end
		vbar.btnDown.Paint = function() end

		frame.FFWL_Refresh = function()
			if IsValid(frame) then RebuildList(scroll) end
		end

		-- Кнопка добавления (зависит от вкладки)
		local addBtn = vgui.Create("DButton", frame)
		addBtn:Dock(BOTTOM)
		addBtn:SetTall(32)
		addBtn:DockMargin(10, 8, 10, 10)
		addBtn:SetText("")
		addBtn.Paint = function(self, w, h)
			local hovered = self:IsHovered()
			draw.RoundedBox(4, 0, 0, w, h, hovered and COL_ACCENT or COL_HEADER)
			local label, col
			if activeTab == "players" then
				label, col = "ADD PLAYER", COL_ACCENT2
			elseif activeTab == "teams" then
				label, col = "ADD TEAM", COL_ACCENT2
			elseif activeTab == "editors" then
				label, col = "ADD EDITOR", COL_ACCENT2
			else
				label, col = "ADD NPC CLASS", COL_ACCENT2
			end
			if hovered then col = Color(15, 20, 25) end
			draw.SimpleText(label, "FFWL_Tab", w / 2, h / 2, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		addBtn.DoClick = function()
			AddActionForTab(activeTab)()
		end

		RebuildList(scroll)
	end

	-- Клавиша E по полю открывает меню (без автоповтора)
	local useKeyHeld = false
	hook.Add("Think", "FFWL_UseKey", function()
		if not input.IsKeyDown(KEY_E) then
			useKeyHeld = false
			return
		end
		if useKeyHeld then return end
		useKeyHeld = true

		if gui.IsGameUIVisible() then return end
		if IsValid(vgui.GetKeyboardFocus()) then return end

		local ent = GetLookedField()
		if not IsValid(ent) then return end
		if not ClientCanEdit(ent) then return end

		OpenMenu(ent)
	end)

	concommand.Add("ffwl_menu", function()
		local ply = LocalPlayer()
		if not IsValid(ply) then return end

		local ent = GetLookedField()

		-- Трейс может поймать платформу-эмиттер: возьмём её поле
		if not IsValid(ent) then
			local traceEnt = ply:GetEyeTrace().Entity
			if IsValid(traceEnt) and traceEnt:GetClass() == PLATFORM_CLASS then
				local field = nil
				if traceEnt.GetFieldEntity then field = traceEnt:GetFieldEntity() end
				if IsValid(field) then ent = field end
			end
		end

		if not IsValid(ent) then
			chat.AddText(Color(255, 100, 100), "[FFWL] Поле не найдено — наведись на силовое поле")
			return
		end

		OpenMenu(ent)
	end)

	hook.Add("OnPlayerChat", "FFWL_ChatCommand", function(ply, text)
		if ply ~= LocalPlayer() then return end
		if text:lower() == "!ffmenu" then
			RunConsoleCommand("ffwl_menu")
			return true
		end
	end)

	properties.Add("ffwl_menu", {
		MenuLabel = "Forcefield Menu",
		MenuIcon = "icon16/shield_add.png",
		Order = 606,

		Filter = function(self, ent, ply)
			if not IsValid(ent) or ent:GetClass() ~= FIELD_CLASS then return false end
			return ClientCanEdit(ent)
		end,

		Action = function(self, ent)
			OpenMenu(ent)
		end
	})
end
