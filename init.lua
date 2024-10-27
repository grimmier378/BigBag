local mq                      = require("mq")
local ImGui                   = require("ImGui")
local shouldDrawGUI           = true
local scriptName              = "BigBag"
local IsRunning               = false

local imgPath                 = string.format("%s/%s/images/bag.png", mq.luaDir, scriptName)
local minImg                  = mq.CreateTexture(imgPath)
-- Constants
local ICON_WIDTH              = 40
local ICON_HEIGHT             = 40
local COUNT_X_OFFSET          = 39
local COUNT_Y_OFFSET          = 23
local EQ_ICON_OFFSET          = 500
local BAG_ITEM_SIZE           = 40
local MIN_SLOTS_WARN          = 3
local INVENTORY_DELAY_SECONDS = 2
local FreeSlots               = 0
local UsedSlots               = 0
-- EQ Texture Animation references
local animItems               = mq.FindTextureAnimation("A_DragItem")
local animBox                 = mq.FindTextureAnimation("A_RecessedBox")

-- Bag Contents
local items                   = {}
local clickies                = {}
local needSort                = true

-- Bag Options
local sort_order              = { name = false, stack = false, }
local clicked                 = false
-- GUI Activities
local show_item_background    = true

local start_time              = os.time()
local filter_text             = ""

local function help_marker(desc)
	ImGui.TextDisabled("(?)")
	if ImGui.IsItemHovered() then
		ImGui.BeginTooltip()
		ImGui.PushTextWrapPos(ImGui.GetFontSize() * 35.0)
		ImGui.TextUnformatted(desc)
		ImGui.PopTextWrapPos()
		ImGui.EndTooltip()
	end
end

-- Sort routines
local function sort_inventory()
	-- Various Sorting
	if sort_order.name and sort_order.stack then
		table.sort(items, function(a, b) return a.Stack() > b.Stack() or (a.Stack() == b.Stack() and a.Name() < b.Name()) end)
	elseif sort_order.stack then
		table.sort(items, function(a, b) return a.Stack() > b.Stack() end)
	elseif sort_order.name then
		table.sort(items, function(a, b) return a.Name() < b.Name() end)
		-- else
		-- table.sort(items)
	end
end

-- The beast - this routine is what builds our inventory.
local function create_inventory()
	if (((os.difftime(os.time(), start_time)) > INVENTORY_DELAY_SECONDS or table.getn(items) == 0) and mq.TLO.Me.FreeInventory() ~= FreeSlots) or clicked then
		start_time = os.time()
		items = {}
		clickies = {}
		local tmpUsedSlots = 0
		for i = 1, 22, 1 do
			local slot = mq.TLO.Me.Inventory(i)
			if slot.ID() ~= nil then
				if slot.Clicky() then
					table.insert(clickies, slot)
				end
			end
		end
		for i = 23, 34, 1 do
			local slot = mq.TLO.Me.Inventory(i)
			if slot.Container() and slot.Container() > 0 then
				for j = 1, (slot.Container()), 1 do
					if (slot.Item(j)()) then
						table.insert(items, slot.Item(j))
						tmpUsedSlots = tmpUsedSlots + 1
						if slot.Item(j).Clicky() then
							table.insert(clickies, slot.Item(j))
						end
					end
				end
			elseif slot.ID() ~= nil then
				table.insert(items, slot) -- We have an item in a bag slot
				tmpUsedSlots = tmpUsedSlots + 1
				if slot.Clicky() then
					table.insert(clickies, slot)
				end
			end
		end

		if tmpUsedSlots ~= UsedSlots then
			UsedSlots = tmpUsedSlots
		end
		FreeSlots = mq.TLO.Me.FreeInventory()
		needSort = true
		clicked = false
	end
end

-- Converts between ItemSlot and /itemnotify pack numbers
local function to_pack(slot_number)
	return "pack" .. tostring(slot_number - 22)
end

-- Converts between ItemSlot2 and /itemnotify numbers
local function to_bag_slot(slot_number)
	return slot_number + 1
end

-- Displays static utilities that always show at the top of the UI
local function display_bag_utilities()
	ImGui.PushItemWidth(200)
	local text, selected = ImGui.InputText("Filter", filter_text)
	ImGui.PopItemWidth()
	if selected then filter_text = string.gsub(text, "[^a-zA-Z0-9'`_-.]", "") or "" end
	text = filter_text
	ImGui.SameLine()
	if ImGui.SmallButton("Clear") then filter_text = "" end
end

-- Display the collapasable menu area above the items
local function display_bag_options()
	if not ImGui.CollapsingHeader("Bag Options") then
		ImGui.NewLine()
		return
	end
	local changed = false
	sort_order.name, changed = ImGui.Checkbox("Name", sort_order.name)
	if changed then
		needSort = true
	end
	ImGui.SameLine()
	help_marker("Order items from your inventory sorted by the name of the item.")
	local pressed = false
	sort_order.stack, pressed = ImGui.Checkbox("Stack", sort_order.stack)
	if pressed then
		needSort = true
	end
	ImGui.SameLine()
	help_marker("Order items with the largest stacks appearing first.")

	if ImGui.Checkbox("Show Slot Background", show_item_background)
	then
		show_item_background = true
	else
		show_item_background = false
	end
	ImGui.SameLine()
	help_marker("Removes the background texture to give your bag a cool modern look.")

	ImGui.SetNextItemWidth(100)
	MIN_SLOTS_WARN = ImGui.InputInt("Min Slots Warning", MIN_SLOTS_WARN, 1, 10)
	ImGui.SameLine()
	help_marker("Minimum number of slots before the warning color is displayed.")


	ImGui.Separator()
	ImGui.NewLine()
end

-- Helper to create a unique hidden label for each button.  The uniqueness is
-- necessary for drag and drop to work correctly.
local function btn_label(item)
	if not item.slot_in_bag then
		return string.format("##slot_%s", item.ItemSlot())
	else
		return string.format("##bag_%s_slot_%s", item.ItemSlot(), item.ItemSlot2())
	end
end

---Draws the individual item icon in the bag.
---@param item item The item object
local function draw_item_icon(item, iconWidth, iconHeight)
	-- Capture original cursor position
	local cursor_x, cursor_y = ImGui.GetCursorPos()
	local offsetX, offsetY = iconWidth - 1, iconHeight / 2
	-- Draw the background box
	if show_item_background then
		ImGui.DrawTextureAnimation(animBox, iconWidth, iconHeight)
	end

	-- This handles our "always there" drop zone (for now...)
	if not item then
		return
	end

	-- Reset the cursor to start position, then fetch and draw the item icon
	ImGui.SetCursorPos(cursor_x, cursor_y)
	animItems:SetTextureCell(item.Icon() - EQ_ICON_OFFSET)
	ImGui.DrawTextureAnimation(animItems, iconWidth, iconHeight)

	-- Overlay the stack size text in the lower right corner
	ImGui.SetWindowFontScale(0.68)
	local TextSize = ImGui.CalcTextSize(tostring(item.Stack()))
	if item.Stack() > 1 then
		ImGui.SetCursorPos((cursor_x + offsetX) - TextSize, cursor_y + offsetY)
		ImGui.DrawTextureAnimation(animBox, TextSize, 4)
		ImGui.SetCursorPos((cursor_x + offsetX) - TextSize, cursor_y + offsetY)
		ImGui.TextUnformatted(tostring(item.Stack()))
	end
	ImGui.SetWindowFontScale(1.0)

	-- Reset the cursor to start position, then draw a transparent button (for drag & drop)
	ImGui.SetCursorPos(cursor_x, cursor_y)

	if item.TimerReady() > 0 then
		ImGui.PushStyleColor(ImGuiCol.Button, 0.3, 0, 0, 0.4)
		ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.3, 0, 0, 0.4)
		ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0.3, 00, 0, 0.3)
	else
		ImGui.PushStyleColor(ImGuiCol.Button, 0, 0, 0, 0)
		ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0, 0.3, 0, 0.2)
		ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0, 0.3, 0, 0.3)
	end
	ImGui.Button(btn_label(item), iconWidth, iconHeight)
	ImGui.PopStyleColor(3)

	-- Tooltip
	if ImGui.IsItemHovered() then
		local charges = item.Charges() or 0
		local clicky = item.Clicky() or 'none'
		ImGui.BeginTooltip()
		ImGui.Text("Item: %s", item.Name())
		ImGui.Text("Qty: %s", item.Stack() or 1)
		ImGui.TextColored(ImVec4(0, 1, 1, 1), "Value: %0.1f Plat ", (item.Value() or 0) / 1000) -- 1000 copper - 1 plat
		ImGui.SameLine()
		ImGui.TextColored(ImVec4(1, 1, 0, 1), 'Trib: %s', (item.Tribute() or 0))
		if clicky ~= 'none' then
			ImGui.SeparatorText("Clicky Info")
			ImGui.TextColored(ImVec4(0, 1, 0, 1), "Clicky: %s", clicky)
			ImGui.TextColored(ImVec4(0, 1, 1, 1), "Charges: %s", charges >= 0 and charges or 'Infinite')
		end
		ImGui.SeparatorText("Click Actions")
		ImGui.Text("Right Click to use item")
		ImGui.Text("Left Click Pick Up item")
		ImGui.Text("Ctrl + Right Click to Inspect Item")
		ImGui.EndTooltip()
	end

	if ImGui.IsItemClicked(ImGuiMouseButton.Left) then
		if item.ItemSlot2() == -1 then
			mq.cmd("/itemnotify " .. item.ItemSlot() .. " leftmouseup")
		else
			print(item.ItemSlot2())
			mq.cmd("/itemnotify in " .. to_pack(item.ItemSlot()) .. " " .. to_bag_slot(item.ItemSlot2()) .. " leftmouseup")
		end
	end

	-- Right-click mouse works on bag items like in-game action
	if ImGui.IsItemClicked(ImGuiMouseButton.Right) then
		if ImGui.IsKeyPressed(ImGuiMod.Ctrl) then
			local link = item.ItemLink('CLICKABLE')()
			mq.cmdf('/executelink %s', link)
		else
			mq.cmdf('/useitem "%s"', item.Name())
			clicked = true
		end
	end
	local function mouse_over_bag_window()
		local window_x, window_y = ImGui.GetWindowPos()
		local mouse_x, mouse_y = ImGui.GetMousePos()
		local window_size_x, window_size_y = ImGui.GetWindowSize()
		return (mouse_x > window_x and mouse_y > window_y) and (mouse_x < window_x + window_size_x and mouse_y < window_y + window_size_y)
	end

	-- Autoinventory any items on the cursor if you click in the bag UI
	if ImGui.IsMouseClicked(ImGuiMouseButton.Left) and mq.TLO.Cursor() and mouse_over_bag_window() then
		mq.cmd("/autoinventory")
	end
end

-- If there is an item on the cursor, display it.
local function display_item_on_cursor()
	if mq.TLO.Cursor() then
		local cursor_item = mq.TLO.Cursor -- this will be an MQ item, so don't forget to use () on the members!
		local mouse_x, mouse_y = ImGui.GetMousePos()
		local window_x, window_y = ImGui.GetWindowPos()
		local icon_x = mouse_x - window_x + 10
		local icon_y = mouse_y - window_y + 10
		local stack_x = icon_x + COUNT_X_OFFSET
		local stack_y = icon_y + COUNT_Y_OFFSET
		local text_size = ImGui.CalcTextSize(tostring(cursor_item.Stack()))
		ImGui.SetCursorPos(icon_x, icon_y)
		animItems:SetTextureCell(cursor_item.Icon() - EQ_ICON_OFFSET)
		ImGui.DrawTextureAnimation(animItems, ICON_WIDTH, ICON_HEIGHT)
		if cursor_item.Stackable() then
			ImGui.SetCursorPos(stack_x, stack_y)
			ImGui.DrawTextureAnimation(animBox, text_size, ImGui.GetTextLineHeight())
			ImGui.SetCursorPos(stack_x - text_size, stack_y)
			ImGui.TextUnformatted(tostring(cursor_item.Stack()))
		end
	end
end

---Handles the bag layout of individual items
local function display_bag_content()
	-- create_inventory()
	ImGui.SetWindowFontScale(1.0)

	ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, ImVec2(0, 0))
	local bag_window_width = ImGui.GetWindowWidth()
	local bag_cols = math.floor(bag_window_width / BAG_ITEM_SIZE)
	local temp_bag_cols = 1

	for index, _ in ipairs(items) do
		if string.match(string.lower(items[index].Name()), string.lower(filter_text)) then
			draw_item_icon(items[index], ICON_WIDTH, ICON_HEIGHT)
			if bag_cols > temp_bag_cols then
				temp_bag_cols = temp_bag_cols + 1
				ImGui.SameLine()
			else
				temp_bag_cols = 1
			end
		end
	end
	ImGui.PopStyleVar()
end

local function display_clickies()
	ImGui.SetWindowFontScale(1.0)

	ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, ImVec2(0, 0))
	local bag_window_width = ImGui.GetWindowWidth()
	local bag_cols = math.floor(bag_window_width / BAG_ITEM_SIZE)
	local temp_bag_cols = 1

	for index, _ in ipairs(clickies) do
		if string.match(string.lower(clickies[index].Name()), string.lower(filter_text)) then
			draw_item_icon(clickies[index], ICON_WIDTH, ICON_HEIGHT)
			if bag_cols > temp_bag_cols then
				temp_bag_cols = temp_bag_cols + 1
				ImGui.SameLine()
			else
				temp_bag_cols = 1
			end
		end
	end
	ImGui.PopStyleVar()
end

local function display_details()
	ImGui.SetWindowFontScale(1.0)
	if ImGui.BeginTable("Details", 7, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.Resizable, ImGuiTableFlags.Hideable, ImGuiTableFlags.Reorderable)) then
		ImGui.TableSetupColumn('Icon', ImGuiTableColumnFlags.WidthStretch)
		ImGui.TableSetupColumn("Name", ImGuiTableColumnFlags.WidthFixed, 100)
		ImGui.TableSetupColumn("Value", ImGuiTableColumnFlags.WidthStretch)
		ImGui.TableSetupColumn('Tribute', ImGuiTableColumnFlags.WidthStretch)
		ImGui.TableSetupColumn('Worn EFX', ImGuiTableColumnFlags.WidthStretch)
		ImGui.TableSetupColumn('Clicky', ImGuiTableColumnFlags.WidthStretch)
		ImGui.TableSetupColumn('Charges', ImGuiTableColumnFlags.WidthStretch)
		ImGui.TableHeadersRow()
		for index, _ in ipairs(items) do
			if string.match(string.lower(items[index].Name()), string.lower(filter_text)) then
				local item = items[index]
				local clicky = item.Clicky() or 'No'
				ImGui.TableNextRow()
				ImGui.TableNextColumn()
				draw_item_icon(item, 20, 20)
				ImGui.TableNextColumn()
				ImGui.TextColored(ImVec4(0, 1, 1, 1), item.Name() or 'Unknown')
				if ImGui.IsItemHovered() and ImGui.IsMouseClicked(ImGuiMouseButton.Left) then
					mq.cmdf('/executelink %s', item.ItemLink('CLICKABLE')())
				end
				ImGui.TableNextColumn()
				ImGui.TextColored(ImVec4(0, 1, 0.5, 1), "%0.2f pp", (item.Value() / 1000) or 0)
				ImGui.TableNextColumn()
				ImGui.Text("%s", item.Tribute() or 0)
				ImGui.TableNextColumn()
				ImGui.Text("%s", item.Worn() or 'No')
				ImGui.TableNextColumn()
				ImGui.TextColored(ImVec4(0, 1, 1, 1), clicky)
				ImGui.TableNextColumn()
				ImGui.Text("%s", clicky and (item.Charges() >= 0 and item.Charges() or 'Infinite') or 'No')
			end
		end
		ImGui.EndTable()
	end
end

local function apply_style()
	ImGui.PushStyleColor(ImGuiCol.Button, .62, .53, .79, .40)
	ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 1, 1, 1, .87)
	ImGui.PushStyleColor(ImGuiCol.ResizeGrip, .62, .53, .79, .40)
	ImGui.PushStyleColor(ImGuiCol.ResizeGripHovered, .62, .53, .79, 1)
	ImGui.PushStyleColor(ImGuiCol.ResizeGripActive, .62, .53, .79, 1)
end

local function renderBtn()
	if FreeSlots > MIN_SLOTS_WARN then
		ImGui.PushStyleColor(ImGuiCol.Button, ImGui.GetStyleColor(ImGuiCol.Button))
		ImGui.PushStyleColor(ImGuiCol.ButtonHovered, ImGui.GetStyleColor(ImGuiCol.ButtonHovered))
	else
		ImGui.PushStyleColor(ImGuiCol.Button, 1.000, 0.354, 0.0, 0.5)
		ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 1.000, 0.354, 0.0, 0.8)
	end
	local openBtn, showBtn = ImGui.Begin(string.format("Big Bag##Mini"), true, bit32.bor(ImGuiWindowFlags.AlwaysAutoResize, ImGuiWindowFlags.NoTitleBar, ImGuiWindowFlags.NoCollapse))
	if not openBtn then
		showBtn = false
	end
	if showBtn then
		if ImGui.ImageButton("BigBag##btn", minImg:GetTextureID(), ImVec2(30, 30)) then
			shouldDrawGUI = not shouldDrawGUI
		end
		if ImGui.IsItemHovered() then
			ImGui.BeginTooltip()
			ImGui.TextUnformatted("Click to Toggle Big Bag")
			ImGui.TextUnformatted("Middle Mouse Click to Toggle GUI")
			ImGui.Text(string.format("Used/Free Slots "))
			ImGui.SameLine()
			ImGui.TextColored(FreeSlots > MIN_SLOTS_WARN and ImVec4(0.354, 1.000, 0.000, 0.500) or ImVec4(1.000, 0.354, 0.0, 0.5), "(%s/%s)", UsedSlots, FreeSlots)
			ImGui.EndTooltip()
		end

		if ImGui.IsMouseClicked(ImGuiMouseButton.Middle) then
			shouldDrawGUI = not shouldDrawGUI
		end
	end

	ImGui.PopStyleColor(5)
	ImGui.End()
end
--- ImGui Program Loop
local function RenderGUI()
	if not IsRunning then return end
	if shouldDrawGUI then
		apply_style()

		local open, show = ImGui.Begin(string.format("Big Bag"), true, ImGuiWindowFlags.NoScrollbar)
		if not open then
			show = false
			shouldDrawGUI = false
		end
		if show then
			display_bag_utilities()
			display_bag_options()
			ImGui.SetWindowFontScale(1.25)
			ImGui.SetCursorPosY(ImGui.GetCursorPosY() - 20)
			ImGui.Text(string.format("Used/Free Slots "))
			ImGui.SameLine()
			ImGui.TextColored(FreeSlots > MIN_SLOTS_WARN and ImVec4(0.354, 1.000, 0.000, 0.500) or ImVec4(1.000, 0.354, 0.0, 0.5), "(%s/%s)", UsedSlots, FreeSlots)

			if ImGui.BeginTabBar("BagTabs") then
				if ImGui.BeginTabItem("Items") then
					display_bag_content()
					ImGui.EndTabItem()
				end
				if ImGui.BeginTabItem('Clickies') then
					display_clickies()
					ImGui.EndTabItem()
				end
				if ImGui.BeginTabItem('Details') then
					display_details()
					ImGui.EndTabItem()
				end
				ImGui.EndTabBar()
			end

			display_item_on_cursor()
		end
		ImGui.PopStyleColor(5)
		ImGui.End()
	end

	renderBtn()
end

local function CommandHandler(...)
	local args = { ..., }
	if args[1]:lower() == "ui" then
		shouldDrawGUI = not shouldDrawGUI
	elseif args[1]:lower() == 'exit' then
		IsRunning = false
	end
end

local function init()
	IsRunning = true

	create_inventory()
	mq.bind("/bigbag", CommandHandler)
	mq.imgui.init("BigBagGUI", RenderGUI)
	printf("%s Loaded", scriptName)
	printf("\aw[\at%s\ax] \atCommands", scriptName)
	printf("\aw[\at%s\ax] \at/bigbag ui \ax- Toggle GUI", scriptName)
	printf("\aw[\at%s\ax] \at/bigbag exit \ax- Exits", scriptName)
end
--- Main Script Loop

local function MainLoop()
	while IsRunning do
		mq.delay("1s")
		create_inventory()
		if needSort then
			sort_inventory()
			needSort = false
		end
	end
end

init()
MainLoop()