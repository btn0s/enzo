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
        set candidates to reminders of list listName whose name is reminderTitle and completed is false
        if (count of candidates) is not 1 then error "Expected exactly one incomplete “" & reminderTitle & "” reminder"
        if (due date of item 1 of candidates) is not targetDate then error "Reminder due date did not persist"
    end tell

    return "verified"
end run
