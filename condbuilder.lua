-- Macro Condition Builder v0.2 - aquietone
-- Uses some basic pattern matching to provide autocompletion with filtering under specific patterns.
-- 1. When input ends "${" then it will provide short list of hardcoded TLOs commonly used in conditions.
-- 2. When input ends in "${TLONAME." then it will provide all available members of the datatype returned by ${TLONAME}.
-- 3. When input ends in "${TLONAME[params]." then it will provide all available members of the datatype returned by ${TLONAME[params]}.
-- 4. When input ends in "${TLONAME.MEMBER[params]." then it will return all available members of the datatype returned by ${TLONAME.MEMBER[params]}.
-- 5. When input ends in "${TLONAME.MEMBER." then it will return all available members of the datatype returned by ${TLONAME.MEMBER}.
-- Anything further nested will not populate available options.

local mq = require('mq')
local imgui = require('ImGui')

local isOpen = true

local expression = ''

-- Random sampling of TLOs that seem more likely to be used in conditions
local TLOOptions = {
    'Me', 'Target', 'Spawn', 'SpawnCount', 'Spell', 'Math',
    'Cursor', 'Defined', 'FindItem', 'Group', 'Raid',
    'If', 'Select', 'Range', 'String', 'Int', 'Bool',
}

local buttons = {
    '${', '}', '[', ']', '(', ')', '.', '!', '&&', '||', '==', '!=', 'Equal', 'NotEqual'
}

local examples = {
    '${Target.Named}',
    '${Me.PctHPs} > 70 && ${Me.PctMana} < 60',
    '${SpawnCount[pc radius 60]} > 3',
    '${Target.CleanName.Equal[Fippy Darkpaw]}',
    '${Select[${Target.Class.ShortName},CLR,DRU,SHM]}',
    '(${Me.XTarget} > 2 || ${Target.Named}) && ${BurnAllNamed}',
    '!${Me.Buff[Illusion Benefit Greater Jann].ID}',
    '${SpawnCount[${Me.Name}`s pet]} > 0',
    '${Me.XTarget} > 0',
}

local function drawReferenceLink()
    if imgui.Button('\xee\x89\x90 TLO Reference') then
        os.execute('start https://docs.macroquest.org/reference/top-level-objects/')
    end
end

local filterType = 'tlo'
local filteredOptions = {}

local COMBO_POPUP_FLAGS = bit32.bor(ImGuiWindowFlags.NoTitleBar, ImGuiWindowFlags.NoMove, ImGuiWindowFlags.NoResize, ImGuiWindowFlags.ChildWindow)
---Draw a combo box with filterable options
---@param label string #The label for the combo
---@param current_value string #The current selected value or filter text for the combo
---@param options table #The selectable options for the combo
---@return string,boolean #Return the selected value or partial filter text as well as whether the value changed
local function ComboFiltered(label, current_value, options)
    local avail = imgui.GetContentRegionAvailVec()
    imgui.SetNextItemWidth(avail.x - ImGui.CalcTextSize(label))
    local result, changed = imgui.InputText(label, current_value, ImGuiInputTextFlags.EnterReturnsTrue)
    local active = imgui.IsItemActive()
    local activated = imgui.IsItemActivated()
    if activated then imgui.OpenPopup('##combopopup'..label) end
    if #filteredOptions > 0 then
        local itemRectMinX, _ = imgui.GetItemRectMin()
        local _, itemRectMaxY = imgui.GetItemRectMax()
        imgui.SetNextWindowPos(itemRectMinX, itemRectMaxY)
        imgui.SetNextWindowSize(avail.x - ImGui.CalcTextSize(label), #filteredOptions > 20 and imgui.GetTextLineHeight()*20 or -1)
        --end
        if imgui.BeginPopup('##combopopup'..label, COMBO_POPUP_FLAGS) then
            for _,value in ipairs(options) do
                if imgui.Selectable(value) then
                    if filterType == 'tlo' then
                        local prefix = expression:match('(.*%${)%w*$')
                        result = prefix .. value
                    elseif filterType == 'member' then
                        local prefix = expression:match('(.*%${%w*%.)%w*$')
                        result = prefix .. value
                    elseif filterType == 'memberafterarg' then
                        local prefix = expression:match('(.*%${%w*%[[%w%d]*%]%.)%w*$')
                        result = prefix .. value
                    elseif filterType == 'memberaftermember' then
                        local prefix = expression:match('(.*%${%w*%.%w*%.)%w*$')
                        result = prefix .. value
                    elseif filterType == 'memberaftermemberwithparam' then
                        local prefix = expression:match('(.*%${%w*%.%w*%[[%w%d]*%]%.)%w*$')
                        result = prefix .. value
                    end
                end
            end
            if changed or (not active and not imgui.IsWindowFocused()) then
                imgui.CloseCurrentPopup()
            end
            imgui.EndPopup()
        end
    end
    return result, current_value ~= result
end

local function populateFilter()
    filteredOptions = {}
    -- Match value ending with pattern ${\w* as possible TLO name
    local tloInput = expression:match('.*%${(%w*)$')
    if tloInput then
        -- Populate dropdown with hardcoded list of TLOs to select from
        for _,tlo in ipairs(TLOOptions) do
            -- Filter the list based on the input following the ${
            if tlo:find(tloInput) then
                table.insert(filteredOptions, tlo)
            end
        end
        filterType = 'tlo'
        return
    end
    -- Match value ending with pattern ${\w*.\w* as possible TLO Member naem
    local tloName, memberInput = expression:match('.*%${(%w*)%.(%w*)$')
    if memberInput and tloName then
        -- Get string name of the TLO data type
        local dataTypeName = mq.gettype(mq.TLO[tloName])
        if dataTypeName then
            -- Get DataType definition for the type name
            local dataType = mq.TLO.Type(dataTypeName)
            for i=0,300 do
                local tloMember = dataType.Member(i)()
                -- Iterate over the members and populate the dropdown with entries matching the input following the ${\w*.
                if tloMember and tloMember:find(memberInput) then
                    table.insert(filteredOptions, tloMember)
                    filteredOptions[tloMember] = true
                end
            end
            -- Repeat for inherited DataType
            if dataType.InheritedType() then
                local parentDataTypeName = mq.TLO.Type(dataType.InheritedType)
                for i=0,300 do
                    local tloMember = parentDataTypeName.Member(i)()
                    if tloMember and not filteredOptions[tloMember] and tloMember:find(memberInput) then
                        table.insert(filteredOptions, tloMember)
                    end
                end
            end
            filterType = 'member'
            table.sort(filteredOptions)
            return
        end
    end
    -- Match values ending with pattern ${\w*[\w\d*].\w* as possible TLO Member name after TLO parameters
    local tloName, param, memberInput = expression:match('.*%${(%w*)%[([%w%d]*)%]%.(%w*)$')
    if tloName and param and memberInput then
        local dataTypeName = mq.gettype(mq.TLO[tloName](param))
        if dataTypeName then
            local dataType = mq.TLO.Type(dataTypeName)
            for i=0,300 do
                local tloMember = dataType.Member(i)()
                if tloMember and tloMember:find(memberInput) then
                    table.insert(filteredOptions, tloMember)
                    filteredOptions[tloMember] = true
                end
            end
            if dataType.InheritedType() then
                local parentDataTypeName = mq.TLO.Type(dataType.InheritedType)
                for i=0,300 do
                    local tloMember = parentDataTypeName.Member(i)()
                    if tloMember and not filteredOptions[tloMember] and tloMember:find(memberInput) then
                        table.insert(filteredOptions, tloMember)
                    end
                end
            end
            filterType = 'memberafterarg'
            table.sort(filteredOptions)
            return
        end
    end
    -- Match values ending with pattern ${\w*.\w*.\w* as possible TLO Member name after TLO member
    local tloName, firstTloMember, memberInput = expression:match('.*%${(%w*)%.(%w*)%.(%w*)$')
    if tloName and firstTloMember and memberInput then
        local dataTypeName = mq.gettype(mq.TLO[tloName][firstTloMember])
        if dataTypeName then
            local dataType = mq.TLO.Type(dataTypeName)
            for i=0,300 do
                local tloMember = dataType.Member(i)()
                if tloMember and tloMember:find(memberInput) then
                    table.insert(filteredOptions, tloMember)
                    filteredOptions[tloMember] = true
                end
            end
            if dataType.InheritedType() then
                local parentDataTypeName = mq.TLO.Type(dataType.InheritedType)
                for i=0,300 do
                    local tloMember = parentDataTypeName.Member(i)()
                    if tloMember and not filteredOptions[tloMember] and tloMember:find(memberInput) then
                        table.insert(filteredOptions, tloMember)
                    end
                end
            end
            filterType = 'memberaftermember'
            table.sort(filteredOptions)
            return
        end
    end
    -- Match values ending with pattern ${\w*.\w*[\w\d*].\w* as possible TLO Member name after TLO member
    local tloName, firstTloMember, param, memberInput = expression:match('.*%${(%w*)%.(%w*)%[([%w%d]*)%]%.(%w*)$')
    if tloName and firstTloMember and param and memberInput then
        local dataTypeName = mq.gettype(mq.TLO[tloName][firstTloMember](param))
        if dataTypeName then
            local dataType = mq.TLO.Type(dataTypeName)
            for i=0,300 do
                local tloMember = dataType.Member(i)()
                if tloMember and tloMember:find(memberInput) then
                    table.insert(filteredOptions, tloMember)
                    filteredOptions[tloMember] = true
                end
            end
            if dataType.InheritedType() then
                local parentDataTypeName = mq.TLO.Type(dataType.InheritedType)
                for i=0,300 do
                    local tloMember = parentDataTypeName.Member(i)()
                    if tloMember and not filteredOptions[tloMember] and tloMember:find(memberInput) then
                        table.insert(filteredOptions, tloMember)
                    end
                end
            end
            filterType = 'memberaftermemberwithparam'
            table.sort(filteredOptions)
            return
        end
    end
end

local function drawButtons()
    imgui.Separator()
    for i,button in ipairs(buttons) do
        if imgui.Button(button) then
            expression = expression .. button
        end
        if i % 7 ~= 0 then
            imgui.SameLine()
        end
    end
end

local function drawExamples()
    imgui.Separator()
    if imgui.BeginCombo('Examples', '') then
        for i,example in ipairs(examples) do
            if imgui.Selectable(example) then
                expression = example
            end
        end
        imgui.EndCombo()
    end
end

local function drawOutput()
    imgui.Separator()
    imgui.Text('Output')
    if imgui.BeginChild('outputchild', -1, -1, ImGuiChildFlags.Border, 0) then
        imgui.Text(mq.parse(expression))
    end
    imgui.EndChild()
end

local function expressionBuilder()
    local isDraw = true
    isOpen, isDraw = imgui.Begin("Macro Condition Builder", isOpen)
    if isDraw then
        drawReferenceLink()
        local changed
        expression, changed = ComboFiltered('Condition', expression, filteredOptions)
        if changed then
            populateFilter()
        end
        drawButtons()
        drawExamples()
        drawOutput()
    end
    imgui.End()
end

mq.imgui.init('condbuilder', expressionBuilder)

while isOpen do
    mq.delay(1000)
end
