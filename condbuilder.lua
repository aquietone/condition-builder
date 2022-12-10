-- Macro Condition Builder v0.2 - aquietone
local mq = require('mq')

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
    if ImGui.Button('\xee\x89\x90 TLO Reference') then
        os.execute('start https://docs.macroquest.org/reference/top-level-objects/')
    end
end

local function drawContextMenu()
    local menuitems = {}
    if expression:len() >= 2 and expression:sub(-2) == '${' then
        -- The string ends with ${ so we can offer up some TLOs as hints
        for _,tlo in ipairs(TLOOptions) do
            table.insert(menuitems, tlo)
        end
    elseif expression:len() > 1 and expression:sub(-1) == '.' then
        -- determine TLO name before the . to lookup members
        local tlo = expression:match('.*[{.](.*)%.')
        if mq.TLO[tlo] then
            -- The string before the trailing . is a valid TLO, so we can offer up
            -- the TLOs members as hints
            local tlotype = mq.gettype(mq.TLO[tlo])
            for i=0,300 do
                local tlomember = mq.TLO.Type(tlotype).Member(i)()
                table.insert(menuitems, tlomember)
            end
        end
    end
    if #menuitems > 20 then
        ImGui.SetNextWindowSize(-1, ImGui.GetTextLineHeight()*20)
    end
    if ImGui.BeginPopupContextItem() then
        if #menuitems == 0 then
            -- Not a TLO. It could be a member or a parameter like 
            -- Me.CleanName. or Spawn[id 123].
            -- Or it could just be something incomplete / invalid
            ImGui.Text('No Suggestions')
        else
            for _,item in ipairs(menuitems) do
                if ImGui.Selectable(item) then
                    expression = expression .. item
                end
            end

        end
        ImGui.EndPopup()
    end
end

local function drawButtons()
    ImGui.Separator()
    for i,button in ipairs(buttons) do
        if ImGui.Button(button) then
            expression = expression .. button
        end
        if i % 7 ~= 0 then
            ImGui.SameLine()
        end
    end
end

local function drawExamples()
    ImGui.Separator()
    if ImGui.BeginCombo('Examples', '') then
        for i,example in ipairs(examples) do
            if ImGui.Selectable(example) then
                expression = example
            end
        end
        ImGui.EndCombo()
    end
end

local function drawOutput()
    ImGui.Separator()
    ImGui.Text('Output')
    if ImGui.BeginChild('outputchild', -1, -1, true) then
        ImGui.Text(mq.parse(expression))
    end
    ImGui.EndChild()
end

local function expressionBuilder()
    local isDraw = true
    isOpen, isDraw = ImGui.Begin("Macro Condition Builder", isOpen)
    if isDraw then
        drawReferenceLink()
        expression = ImGui.InputTextWithHint('Condition', '${Target.Named}', expression)
        drawContextMenu()
        drawButtons()
        drawExamples()
        drawOutput()
    end
    ImGui.End()
end

mq.imgui.init('condbuilder', expressionBuilder)

while isOpen do
    mq.delay(1000)
end
