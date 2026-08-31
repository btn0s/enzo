on run argv
    if (count of argv) is not 8 then error "Expected list, title, year, month, day, hour, minute, second"

    set listName to item 1 of argv
    set reminderTitle to item 2 of argv
    set dueYear to (item 3 of argv) as integer
    set dueMonth to (item 4 of argv) as integer
    set dueDay to (item 5 of argv) as integer
    set dueHour to (item 6 of argv) as integer
    set dueMinute to (item 7 of argv) as integer
    set dueSecond to (item 8 of argv) as integer

    set targetDate to current date
    set year of targetDate to dueYear
    set month of targetDate to dueMonth
    set day of targetDate to dueDay
    set hours of targetDate to dueHour
    set minutes of targetDate to dueMinute
    set seconds of targetDate to dueSecond

    tell application "Reminders"
        if not (exists list listName) then error "Reminders list not found: " & listName
        set targetList to list listName
        set candidates to reminders of targetList whose name is reminderTitle and completed is false
        if (count of candidates) is greater than 1 then error "More than one incomplete “" & reminderTitle & "” reminder exists"
        if (count of candidates) is 0 then
            set targetReminder to make new reminder at end of reminders of targetList with properties {name:reminderTitle, body:"Moved automatically after each logged feeding."}
        else
            set targetReminder to item 1 of candidates
        end if
        set completed of targetReminder to false
        set due date of targetReminder to targetDate
        set remind me date of targetReminder to targetDate
        show targetReminder
        activate
    end tell

    my enableUrgent(reminderTitle)
    return "updated"
end run

on enableUrgent(reminderTitle)
    tell application "System Events"
        tell process "Reminders"
            set frontmost to true
            repeat 40 times
                try
                    set reminderOutline to UI element 1 of UI element 1 of UI element 3 of splitter group 1 of window "Reminders"
                    repeat with reminderRow in rows of reminderOutline
                        try
                            set cellElement to UI element 1 of reminderRow
                            if (description of cellElement as text) starts with ("Incomplete, " & reminderTitle & ",") then
                                set rowContainer to UI element 1 of cellElement
                                set openPopovers to every UI element of rowContainer whose role is "AXPopover"
                                if (count of openPopovers) is 0 then
                                    click first button of rowContainer whose description is "Edit Details"
                                else
                                    set detailsPopover to item 1 of openPopovers
                                    set outerScrollArea to UI element 1 of detailsPopover
                                    set contentArea to UI element 1 of outerScrollArea
                                    set dateAndTimeGroup to UI element 3 of contentArea
                                    -- Urgent is the last switch. When enabled, Reminders inserts
                                    -- an “Alarm on: …” label immediately before it.
                                    set dateAndTimeSwitches to every UI element of dateAndTimeGroup whose role is "AXCheckBox"
                                    set urgentControl to item -1 of dateAndTimeSwitches
                                    if (role of urgentControl as text) is not "AXCheckBox" then error "Urgent switch moved"
                                    if (value of urgentControl as integer) is 0 then
                                        click urgentControl
                                        delay 0.3
                                    end if
                                    if (value of urgentControl as integer) is not 1 then error "Urgent did not turn on"
                                    -- The details button toggles the popover closed and commits it.
                                    -- Escape cancels, and clicking the row's cell marks it complete.
                                    click first button of rowContainer whose description is "Edit Details"
                                    delay 0.3
                                    if (description of cellElement as text) does not contain ", Urgent," then error "Urgent did not persist"
                                    return
                                end if
                            end if
                        end try
                    end repeat
                end try
                delay 0.1
            end repeat
        end tell
    end tell
    error "Could not find the Urgent control in Reminders"
end enableUrgent
